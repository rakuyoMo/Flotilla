import AppKit

// MARK: - FolderNavigationBackButton

/// 标题区里的返回按钮：圆角矩形底色，中间是向左的 chevron；悬停不变，按下时底色改变，在按钮上抬起才触发
///
/// 深色外观下底色是半透明白色；浅色外观下是不透明的白色，外有一圈暗线与很窄的投影
@MainActor
final class FolderNavigationBackButton: NSView {
    /// chevron 的线宽
    private static let chevronLineWidth: CGFloat = 1.5

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
        setAccessibilityLabel("返回")
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

        // 底色可见部分：深色铺满整个按钮，浅色四周内缩，下方留出投影的位置；按钮不是 flipped，底边内缩加在 minY 上
        let bezel = CGRect(
            x: bounds.minX + insets.left,
            y: bounds.minY + insets.bottom,
            width: bounds.width - insets.left - insets.right,
            height: bounds.height - insets.top - insets.bottom
        )

        drawBezel(bezel, appearance: appearance)
        drawChevron(centeredIn: bezel, color: appearance.backButtonChevronColor)
    }

    /// 面板不是 key window 时，第一次点击也直接生效
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    /// 按下：进入按下状态
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
        let radius = FolderPanelMetrics.backButtonCornerRadius
        let borderOpacity = appearance.backButtonBorderOpacity

        // 有暗线时底色再向内缩 1 像素，暗线落在底色外侧、直接叠在材质上
        let pixel = 1 / (window?.backingScaleFactor ?? 2)
        let inset = borderOpacity > 0 ? pixel : 0

        let fill = NSBezierPath(
            roundedRect: bezel.insetBy(dx: inset, dy: inset),
            xRadius: radius - inset,
            yRadius: radius - inset
        )

        // 投影由不透明的底色投下，只露出底色之外的部分
        NSGraphicsContext.saveGraphicsState()
        appearance.backButtonShadow?.set()

        appearance.backButtonFillColor(isPressed: isPressed).setFill()
        fill.fill()

        NSGraphicsContext.restoreGraphicsState()

        guard borderOpacity > 0 else { return }

        // 暗线是可见部分减去底色剩下的一圈
        let border = NSBezierPath(roundedRect: bezel, xRadius: radius, yRadius: radius)
        border.append(fill)
        border.windingRule = .evenOdd

        NSColor(white: 0, alpha: borderOpacity).setFill()
        border.fill()
    }

    /// 画向左的 chevron：两条边与水平方向成 45°，宽度是高度的一半
    /// - Parameters:
    ///   - rect: chevron 居中的区域
    ///   - color: 线的颜色
    private func drawChevron(centeredIn rect: CGRect, color: NSColor) {
        let height = FolderPanelMetrics.backChevronHeight

        let chevron = NSBezierPath()
        chevron.move(to: CGPoint(x: rect.midX + height / 4, y: rect.midY + height / 2))
        chevron.line(to: CGPoint(x: rect.midX - height / 4, y: rect.midY))
        chevron.line(to: CGPoint(x: rect.midX + height / 4, y: rect.midY - height / 2))

        chevron.lineWidth = Self.chevronLineWidth
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round

        color.setStroke()
        chevron.stroke()
    }

    /// 事件发生的位置是否在按钮内
    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }
}
