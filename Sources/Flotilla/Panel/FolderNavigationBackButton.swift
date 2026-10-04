import AppKit

// MARK: - FolderNavigationBackButton

/// 标题区里的返回按钮：连续曲率圆角的底色上是一个向左的 chevron；悬停不变，按下时底色改变，在按钮上抬起才触发
///
/// 深色外观下底色是半透明白色；浅色外观下是不透明的白色，外有一圈暗线与很窄的投影
@MainActor
final class FolderNavigationBackButton: NSView {
    /// 点击后执行的动作
    private let clickHandler: () -> Void

    /// 是否处于按下状态：按下后拖出按钮即恢复，拖回来再次按下
    private var isPressed = false {
        didSet {
            needsDisplay = true
        }
    }

    /// 创建返回按钮
    /// - Parameter clickHandler: 在按钮上按下并抬起后执行
    init(clickHandler: @escaping () -> Void) {
        self.clickHandler = clickHandler

        super.init(frame: .zero)

        setAccessibilityRole(.button)
        setAccessibilityLabel(
            String(
                localized: "panel.back",
                comment: "面板标题区返回按钮的辅助功能标签，回到上一层文件夹"
            )
        )
    }

    /// 按钮完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 按当前外观画底色与 chevron
    override func draw(_: NSRect) {
        let appearance = FolderPanelAppearance(effectiveAppearance)
        let insets = appearance.backButtonBezelInsets

        // 底色可见部分：深色贴 frame 顶边、最下面 1 pt 不画，浅色再向内缩、下方留出投影的位置；
        // 按钮不是 flipped，底边内缩加在 minY 上
        let bezel = CGRect(
            x: bounds.minX + insets.left,
            y: bounds.minY + insets.bottom,
            width: bounds.width - insets.left - insets.right,
            height: bounds.height - insets.top - insets.bottom
        )

        drawBezel(bezel, appearance: appearance)
        drawChevron(in: bezel, appearance: appearance)
    }

    /// 面板不是 key window 时，第一次点击也直接生效
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    /// 按下：底色换成按下时的颜色，等抬起才判定是否算一次点击
    override func mouseDown(with _: NSEvent) {
        isPressed = true
    }

    /// 拖动：只在鼠标仍位于按钮内时保持按下状态
    override func mouseDragged(with event: NSEvent) {
        isPressed = contains(event)
    }

    /// 抬起：鼠标仍位于按钮内才算一次点击
    override func mouseUp(with event: NSEvent) {
        isPressed = false

        guard contains(event) else { return }

        clickHandler()
    }
}

// MARK: - Private

extension FolderNavigationBackButton {
    /// 画底色，以及浅色外观下底色外的暗线与投影
    /// - Parameters:
    ///   - bezel: 底色可见部分，含暗线
    ///   - appearance: 当前外观
    private func drawBezel(_ bezel: CGRect, appearance: FolderPanelAppearance) {
        let radius = appearance.backButtonCornerRadius
        let borderOpacity = appearance.backButtonBorderOpacity

        // 有暗线时底色再向内缩 1 像素，暗线落在底色外侧、直接叠在材质上；圆角同心，半径随之减小
        let pixel = 1 / (window?.backingScaleFactor ?? 2)
        let inset = borderOpacity > 0 ? pixel : 0

        let fill = Self.roundedPath(
            in: bezel.insetBy(dx: inset, dy: inset),
            radius: radius - inset
        )

        // 投影由不透明的底色投下，只露出底色之外的部分
        NSGraphicsContext.saveGraphicsState()
        appearance.backButtonShadow?.set()

        appearance.backButtonFillColor(isPressed: isPressed).setFill()
        fill.fill()

        NSGraphicsContext.restoreGraphicsState()

        guard borderOpacity > 0 else { return }

        // 暗线是可见部分减去底色剩下的一圈
        let border = Self.roundedPath(in: bezel, radius: radius)
        border.append(fill)
        border.windingRule = .evenOdd

        NSColor(white: 0, alpha: borderOpacity).setFill()
        border.fill()
    }

    /// 画向左的 chevron：两条边与水平方向成 45°，宽度是高度的一半，线端与拐角都是圆的
    ///
    /// 竖直方向以底色中心为中心；水平方向按实测偏向左侧，两种外观下位置相同
    /// - Parameters:
    ///   - rect: 底色可见部分，含暗线
    ///   - appearance: 当前外观
    private func drawChevron(in rect: CGRect, appearance: FolderPanelAppearance) {
        let height = FolderPanelMetrics.backChevronHeight
        let width = height / 2

        // 外接框（不含线宽）的水平中心偏离底色中心；顶点在左，两个端点在右
        let centerX = rect.midX + FolderPanelMetrics.backChevronOffsetX
        let vertexX = centerX - width / 2
        let endX = centerX + width / 2

        let chevron = NSBezierPath()
        chevron.move(to: CGPoint(x: endX, y: rect.midY + height / 2))
        chevron.line(to: CGPoint(x: vertexX, y: rect.midY))
        chevron.line(to: CGPoint(x: endX, y: rect.midY - height / 2))

        chevron.lineWidth = appearance.backButtonChevronLineWidth
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round

        appearance.backButtonChevronColor.setStroke()
        chevron.stroke()
    }

    /// 事件发生的位置是否在按钮内
    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }
}

// MARK: - Helpers

extension FolderNavigationBackButton {
    /// 四个角都是连续曲率圆角的矩形
    /// - Parameters:
    ///   - rect: 外框
    ///   - radius: 圆角半径
    private static func roundedPath(in rect: CGRect, radius: CGFloat) -> NSBezierPath {
        // 从 minY 边上右侧圆角的起点出发，绕过四个角后闭合回到这里
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.maxX - radius * ContinuousCorner.extent, y: rect.minY))

        ContinuousCorner.addCorners(to: path, in: rect, radius: radius)
        path.closeSubpath()

        return NSBezierPath(cgPath: path)
    }
}
