import AppKit
import QuartzCore

// MARK: - FolderPanelBackgroundView

/// 面板的背景，也是面板的 contentView：圆角矩形加一个指向 tile 的尾巴合成一条路径，材质与内容都按它裁剪，边缘描 1 像素的线
///
/// 每一层内容放进 `contentContainer`，位于主体区域 `bodyRect` 内
@MainActor
final class FolderPanelBackgroundView: NSView {
    #warning("TODO: 待实测 圆角 20、尾巴 24×12、描边颜色与粗细；玻璃材质能否按遮罩裁剪成带尾巴的形状")

    /// 放置每一层内容的容器，铺满整个视图，与材质一起按面板形状裁剪
    let contentContainer = NSView()

    /// 尾巴尖端，AppKit 屏幕坐标；布局时按窗口位置换算到自身坐标系，面板尺寸动画期间尖端保持不动
    var tailTip = CGPoint.zero {
        didSet {
            needsLayout = true
        }
    }

    /// Dock 所贴的屏幕边，决定尾巴长在哪条边上
    var edge = DockEdge.bottom {
        didSet {
            needsLayout = true
        }
    }

    /// 材质视图：macOS 26 起为玻璃，此前为 popover 材质
    private let materialView: NSView

    /// 裁剪玻璃材质的遮罩；`NSVisualEffectView` 改用 `maskImage`
    private let materialMask = CAShapeLayer()

    /// 裁剪内容与描边的遮罩
    private let contentMask = CAShapeLayer()

    /// 沿面板轮廓的描边
    private let borderLayer = CAShapeLayer()

    /// 主体区域：去掉尾巴后的圆角矩形，自身坐标系
    var bodyRect: CGRect {
        bounds.divided(atDistance: FolderPanelMetrics.tailHeight, from: edge.rectEdge).remainder
    }

    /// 创建背景，搭好材质、内容容器与描边
    init() {
        materialView = Self.makeMaterialView()

        super.init(frame: .zero)

        wantsLayer = true

        materialView.autoresizingMask = [.width, .height]
        addSubview(materialView)

        // 描边放在内容容器的图层里，与内容共用一个遮罩；遮罩切掉线宽的一半，线宽取 2 像素，留下的恰好 1 像素
        borderLayer.fillColor = nil
        contentContainer.autoresizingMask = [.width, .height]
        contentContainer.wantsLayer = true
        contentContainer.layer?.mask = contentMask
        contentContainer.layer?.addSublayer(borderLayer)

        // 玻璃只保证它的 contentView 位于玻璃效果之内，内容容器因此交给它；popover 材质直接作为父视图
        if #available(macOS 26, *), let glassView = materialView as? NSGlassEffectView {
            glassView.contentView = contentContainer
            glassView.wantsLayer = true
            glassView.layer?.mask = materialMask
        } else {
            materialView.addSubview(contentContainer)
        }

        updateBorderColor()
    }

    /// 背景完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 面板轮廓：主体圆角矩形在面向 Dock 的边上长出尾巴，合成一条闭合路径，描边时尾巴与主体之间没有接缝
    ///
    /// 尾巴底边的中点取尖端在这条边上的投影，并夹在两端圆角之间；尖端偏出时尾巴变斜，尖端仍对准 tile
    /// - Parameters:
    ///   - bodyRect: 主体区域
    ///   - tailTip: 尾巴尖端，与 bodyRect 同一坐标系
    ///   - edge: Dock 所贴的屏幕边
    static func outlinePath(bodyRect: CGRect, tailTip: CGPoint, edge: DockEdge) -> CGPath {
        // 主体四角按逆时针排列：左下、右下、右上、左上
        let corners = [
            CGPoint(x: bodyRect.minX, y: bodyRect.minY),
            CGPoint(x: bodyRect.maxX, y: bodyRect.minY),
            CGPoint(x: bodyRect.maxX, y: bodyRect.maxY),
            CGPoint(x: bodyRect.minX, y: bodyRect.maxY),
        ]

        // 面向 Dock 的边从 corners[side] 走向 corners[side + 1]，逆时针绕行时尾巴恰好在这条边上
        let side =
            switch edge {
            case .bottom:
                0

            case .right:
                1

            case .left:
                3
            }

        let start = corners[side]
        let end = corners[(side + 1) % corners.count]
        let length = hypot(end.x - start.x, end.y - start.y)
        guard length > 0 else { return CGPath(rect: bodyRect, transform: nil) }

        let direction = CGPoint(x: (end.x - start.x) / length, y: (end.y - start.y) / length)

        // 圆角不超过短边的一半，并给尾巴底边留出直边；空文件夹的小面板会因此缩小圆角
        let tailWidth = min(FolderPanelMetrics.tailWidth, length)
        let radius = max(
            0,
            min(FolderPanelMetrics.cornerRadius, bodyRect.width / 2, bodyRect.height / 2, (length - tailWidth) / 2)
        )

        // 尾巴底边的中点：尖端在这条边上的投影，夹在两端圆角之间
        let halfWidth = tailWidth / 2
        let projection = (tailTip.x - start.x) * direction.x + (tailTip.y - start.y) * direction.y
        let center = min(max(projection, radius + halfWidth), length - radius - halfWidth)

        let path = CGMutablePath()
        path.move(to: CGPoint(
            x: start.x + direction.x * (center - halfWidth),
            y: start.y + direction.y * (center - halfWidth)
        ))
        path.addLine(to: tailTip)
        path.addLine(to: CGPoint(
            x: start.x + direction.x * (center + halfWidth),
            y: start.y + direction.y * (center + halfWidth)
        ))

        // 从这条边的终点开始依次绕过四个角，最后回到这条边上
        for offset in 1 ... corners.count {
            path.addArc(
                tangent1End: corners[(side + offset) % corners.count],
                tangent2End: corners[(side + offset + 1) % corners.count],
                radius: radius
            )
        }
        path.closeSubpath()

        return path
    }

    /// 按当前尺寸、尾巴位置重建遮罩与描边
    override func layout() {
        super.layout()

        let origin = window?.frame.origin ?? .zero
        let localTailTip = CGPoint(x: tailTip.x - origin.x, y: tailTip.y - origin.y)
        let path = Self.outlinePath(bodyRect: bodyRect, tailTip: localTailTip, edge: edge)
        let pixelWidth = 1 / (window?.backingScaleFactor ?? 2)

        // 形状跟随窗口尺寸逐帧变化，关掉图层的隐式动画，避免遮罩落后于窗口
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for shapeLayer in [materialMask, contentMask, borderLayer] {
            shapeLayer.frame = bounds
            shapeLayer.path = path
        }
        borderLayer.lineWidth = 2 * pixelWidth

        CATransaction.commit()

        if let effectView = materialView as? NSVisualEffectView {
            effectView.maskImage = Self.maskImage(for: path, size: bounds.size)
        }
    }

    /// 浅色、深色外观切换时更新描边颜色
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()

        updateBorderColor()
    }
}

// MARK: - Private

extension FolderPanelBackgroundView {
    /// 按当前外观解析描边颜色：`CGColor` 不会随外观自动变化，每次切换都要重新解析
    private func updateBorderColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            borderLayer.strokeColor = NSColor.separatorColor.cgColor
        }
    }
}

// MARK: - Helpers

extension FolderPanelBackgroundView {
    /// 创建材质视图：macOS 26 起用玻璃，此前用 popover 材质
    private static func makeMaterialView() -> NSView {
        if #available(macOS 26, *) {
            return NSGlassEffectView()
        }

        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        return effectView
    }

    /// 把轮廓画成 `NSVisualEffectView` 的遮罩图：behind-window 材质由窗口服务器合成，图层遮罩对它无效
    private static func maskImage(for path: CGPath, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            context.addPath(path)
            context.setFillColor(.black)
            context.fillPath()
            return true
        }
    }
}
