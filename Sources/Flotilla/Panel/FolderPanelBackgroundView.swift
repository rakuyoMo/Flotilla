import AppKit
import QuartzCore

// MARK: - FolderPanelBackgroundView

/// 面板的一个层级：圆角矩形加指向 tile 的尾巴合成一条轮廓，自下而上依次是阴影、材质与内容、边缘线
///
/// 每个层级的背景、标题区与网格是一个整体，进入下一层、返回上一层时整体缩放与淡入淡出；
/// 视图四周比轮廓多出 `shadowMargin`，留给阴影
@MainActor
final class FolderPanelBackgroundView: NSView {
    #warning("TODO: 未能实测 macOS 15 的 popover 材质")

    /// 放置标题区与网格的视图，frame 即面板主体
    let bodyView = NSView()

    /// 面板轮廓，自身坐标系
    private let outline: CGPath

    /// 材质视图：macOS 26 起为玻璃，此前为 popover 材质
    private let materialView: NSView

    /// 阴影所在的一层，位于材质之下
    private let shadowView = FolderPanelDecorationView()

    /// 边缘线所在的一层，位于材质与内容之上
    private let edgeView = FolderPanelDecorationView()

    /// 投下阴影的图层；遮罩挖掉轮廓内部，半透明的材质下面不会透出阴影
    private let shadowLayer = CALayer()

    /// 轮廓外侧的暗线，竖直边上最强
    private let shadeLayer = CAShapeLayer()

    /// 水平边外侧的暗线，只有浅色外观有
    private let horizontalShadeLayer = CAShapeLayer()

    /// 轮廓内侧自外向内的几道 1 像素亮线，集中在水平边，外面的更亮
    private let highlightLayers = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]

    /// 创建一个层级的背景
    /// - Parameters:
    ///   - frame: 视图的 frame，包含轮廓与阴影留白
    ///   - bodyRect: 面板主体，自身坐标系
    ///   - tailTip: 尾巴尖端，自身坐标系
    ///   - edge: Dock 所贴的屏幕边，决定尾巴长在哪条边上
    init(frame: CGRect, bodyRect: CGRect, tailTip: CGPoint, edge: DockEdge) {
        outline = Self.outlinePath(bodyRect: bodyRect, tailTip: tailTip, edge: edge)
        materialView = Self.makeMaterialView()

        super.init(frame: frame)

        wantsLayer = true

        let bounds = CGRect(origin: .zero, size: frame.size)

        for decorationView in [shadowView, materialView, edgeView] {
            decorationView.frame = bounds
            decorationView.autoresizingMask = [.width, .height]
        }

        buildShadow(in: bounds)
        buildEdges(in: bounds)
        buildMaterial(bodyRect: bodyRect, in: bounds)

        // 自下而上叠放：阴影、材质与内容、边缘线
        addSubview(shadowView)
        addSubview(materialView)
        addSubview(edgeView)
    }

    /// 背景完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("不支持从归档解码")
    }

    /// 面板轮廓：主体是连续曲率的圆角矩形，面向 Dock 的边上长出尾巴，合成一条闭合路径
    ///
    /// 在“尾巴朝下”的标准坐标系里构造，再旋转到 Dock 所在的方向；
    /// 尾巴底边的中点取尖端在这条边上的投影，并夹在两端圆角之间，尖端偏出时尾巴变斜，尖端仍对准 tile；
    /// tile 离屏幕边缘近到尾巴斜到极限时，尖端停在极限处
    /// - Parameters:
    ///   - bodyRect: 主体区域
    ///   - tailTip: 尾巴尖端，与 bodyRect 同一坐标系
    ///   - edge: Dock 所贴的屏幕边
    static func outlinePath(
        bodyRect: CGRect,
        tailTip: CGPoint,
        edge: DockEdge
    ) -> CGPath {
        var transform = canonicalTransform(bodyRect: bodyRect, edge: edge)
        let canonicalTip = tailTip.applying(transform.inverted())

        // 标准坐标系里面向 Dock 的边沿 x 轴，长度为 length；主体向 y 正方向延伸 depth
        let (length, depth) = edge == .bottom
            ? (bodyRect.width, bodyRect.height)
            : (bodyRect.height, bodyRect.width)

        let radius = min(
            FolderPanelMetrics.cornerRadius,
            min(length, depth) / 2 / ContinuousCorner.extent
        )
        let cornerLength = radius * ContinuousCorner.extent

        let path = CGMutablePath()
        path.move(to: CGPoint(x: cornerLength, y: 0))

        addTail(to: path, tip: canonicalTip, edgeLength: length, cornerLength: cornerLength)
        path.addLine(to: CGPoint(x: length - cornerLength, y: 0))

        // 从面向 Dock 的边的右端起，依次绕过主体的四个角，回到这条边的左端
        ContinuousCorner.addCorners(
            to: path,
            in: CGRect(x: 0, y: 0, width: length, height: depth),
            radius: radius
        )

        path.closeSubpath()

        return path.copy(using: &transform) ?? path
    }

    /// 点是否落在面板轮廓之内
    /// - Parameter point: 自身坐标系
    func contains(_ point: CGPoint) -> Bool {
        outline.contains(point)
    }

    /// 按窗口的像素密度重建边缘线：线宽是 1 像素
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()

        updateEdges()
    }

    /// 系统外观变化时，边缘线与阴影换成对应外观的深浅
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()

        updateColors()
    }
}

// MARK: - Private

extension FolderPanelBackgroundView {
    /// 阴影：图层按轮廓投影，遮罩只留轮廓外侧
    private func buildShadow(in bounds: CGRect) {
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = outline
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowRadius = FolderPanelMetrics.shadowRadius
        shadowLayer.shadowOffset = CGSize(width: 0, height: -FolderPanelMetrics.shadowOffset)

        let outsideMask = CAShapeLayer()
        outsideMask.frame = bounds

        let maskPath = CGMutablePath()
        maskPath.addRect(bounds)
        maskPath.addPath(outline)

        outsideMask.path = maskPath
        outsideMask.fillRule = .evenOdd
        shadowLayer.mask = outsideMask

        shadowView.layer?.addSublayer(shadowLayer)
    }

    /// 边缘线：暗线在轮廓外侧，亮线在轮廓内侧，自外向内逐道变弱
    private func buildEdges(in bounds: CGRect) {
        for edgeLayer in [shadeLayer, horizontalShadeLayer] + highlightLayers {
            edgeLayer.frame = bounds
            edgeView.layer?.addSublayer(edgeLayer)
        }

        updateColors()
        updateEdges()
    }

    /// 按当前外观设置边缘线的颜色与阴影的深浅
    private func updateColors() {
        let appearance = FolderPanelAppearance(effectiveAppearance)

        shadowLayer.shadowOpacity = appearance.shadowOpacity

        shadeLayer.fillColor = NSColor(
            white: 0,
            alpha: appearance.edgeShadeOpacity
        ).cgColor

        horizontalShadeLayer.fillColor = NSColor(
            white: 0,
            alpha: appearance.horizontalEdgeShadeOpacity
        ).cgColor

        for (layer, opacity) in zip(highlightLayers, appearance.edgeHighlightOpacities) {
            layer.fillColor = NSColor(white: 1, alpha: opacity).cgColor
        }
    }

    /// 按当前像素密度计算边缘线的区域
    ///
    /// 轮廓左右各平移 1 像素后多出来的部分，宽度随边的朝向变化：竖直边上满 1 像素，水平边上为 0，暗线因此集中在竖直边；
    /// 上下平移后多出来的部分同理集中在水平边；亮线取上下平移后缺掉的部分，同样集中在水平边；尾巴斜边几种兼有
    private func updateEdges() {
        let scale = window?.backingScaleFactor ?? 2
        let pixel = 1 / scale

        let shifted = { (dx: CGFloat, dy: CGFloat) in
            var transform = CGAffineTransform(translationX: dx, y: dy)
            return self.outline.copy(using: &transform) ?? self.outline
        }

        // 上下各平移 n 像素后仍重合的部分，即轮廓去掉水平边上 n 像素后剩下的区域
        let core = { (pixels: CGFloat) in
            shifted(0, -pixels * pixel).intersection(shifted(0, pixels * pixel))
        }

        shadeLayer.path = shifted(-pixel, 0)
            .union(shifted(pixel, 0))
            .subtracting(outline)

        horizontalShadeLayer.path = shifted(0, -pixel)
            .union(shifted(0, pixel))
            .subtracting(outline)

        // 第 n 道亮线是轮廓去掉水平边上 n - 1 像素与 n 像素之间的一圈，每道宽 1 像素，紧贴上一道的内侧
        for (index, layer) in highlightLayers.enumerated() {
            let outer = index == 0 ? outline : core(CGFloat(index))

            layer.path = outer.subtracting(core(CGFloat(index + 1)))
        }

        for layer in [shadowLayer, shadeLayer, horizontalShadeLayer] + highlightLayers {
            layer.contentsScale = scale
        }
    }

    /// 材质：按轮廓裁剪，标题区与网格放在主体区域里
    private func buildMaterial(bodyRect: CGRect, in bounds: CGRect) {
        let contentView = NSView(frame: bounds)
        contentView.autoresizingMask = [.width, .height]

        bodyView.frame = bodyRect
        contentView.addSubview(bodyView)

        // 玻璃把内容放进它的 contentView，整体用图层遮罩裁成轮廓；
        // behind-window 的 popover 材质由窗口服务器合成，图层遮罩对它无效，只能用 maskImage
        if
            #available(macOS 26, *),
            let glassView = materialView as? NSGlassEffectView
        {
            let mask = CAShapeLayer()
            mask.frame = bounds
            mask.path = outline

            glassView.contentView = contentView
            glassView.wantsLayer = true
            glassView.layer?.mask = mask
        } else if let effectView = materialView as? NSVisualEffectView {
            effectView.maskImage = Self.maskImage(for: outline, size: bounds.size)
            effectView.addSubview(contentView)
        }
    }
}

// MARK: - Helpers

extension FolderPanelBackgroundView {
    /// 从“尾巴朝下”的标准坐标系到 bodyRect 所在坐标系的变换
    ///
    /// 标准坐标系里主体占据 `[0, length] × [0, depth]`，面向 Dock 的边在 y = 0，尾巴朝 y 负方向
    private static func canonicalTransform(
        bodyRect: CGRect,
        edge: DockEdge
    ) -> CGAffineTransform {
        switch edge {
        case .bottom:
            CGAffineTransform(translationX: bodyRect.minX, y: bodyRect.minY)

        // 面向 Dock 的边是主体左边，自上而下：(x, y) → (minX + y, maxY - x)
        case .left:
            CGAffineTransform(
                a: 0,
                b: -1,
                c: 1,
                d: 0,
                tx: bodyRect.minX,
                ty: bodyRect.maxY
            )

        // 面向 Dock 的边是主体右边，自下而上：(x, y) → (maxX - y, minY + x)
        case .right:
            CGAffineTransform(
                a: 0,
                b: 1,
                c: -1,
                d: 0,
                tx: bodyRect.maxX,
                ty: bodyRect.minY
            )
        }
    }

    /// 在 y = 0 的边上添加尾巴：两条斜边与边相接处内凹倒圆，尖端倒圆后恰好到达 tip
    private static func addTail(
        to path: CGMutablePath,
        tip: CGPoint,
        edgeLength: CGFloat,
        cornerLength: CGFloat
    ) {
        let halfBase = FolderPanelMetrics.tailBaseWidth / 2
        let tipRadius = FolderPanelMetrics.tailTipRadius
        let filletRadius = FolderPanelMetrics.tailFilletRadius

        // 底边中点夹在两端圆角之间，给内凹倒圆留出位置
        let margin = cornerLength + halfBase + filletRadius
        let center = min(max(tip.x, margin), max(margin, edgeLength - margin))

        // 尖端最多偏到底边端点内侧半个尖端圆角处：再偏，尖端倒圆与根部内凹倒圆会在较短的斜边上重叠，轮廓折回
        let reach = halfBase - tipRadius / 2
        let apexX = min(max(tip.x, center - reach), center + reach)

        // 90° 尖角倒圆后，最低点比尖角高出 r(√2 - 1)，尖角因此要比 tip 再低这么多
        let apex = CGPoint(x: apexX, y: tip.y - tipRadius * (2.0.squareRoot() - 1))

        path.addArc(
            tangent1End: CGPoint(x: center - halfBase, y: 0),
            tangent2End: apex,
            radius: filletRadius
        )

        path.addArc(
            tangent1End: apex,
            tangent2End: CGPoint(x: center + halfBase, y: 0),
            radius: tipRadius
        )

        path.addArc(
            tangent1End: CGPoint(x: center + halfBase, y: 0),
            tangent2End: CGPoint(x: edgeLength, y: 0),
            radius: filletRadius
        )
    }

    /// 创建材质视图：macOS 26 起用玻璃，此前用 popover 材质
    private static func makeMaterialView() -> NSView {
        if #available(macOS 26, *) {
            let glassView = NSGlassEffectView()
            glassView.style = .regular

            return glassView
        }

        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active

        return effectView
    }

    /// 把轮廓画成 `NSVisualEffectView` 的遮罩图
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
