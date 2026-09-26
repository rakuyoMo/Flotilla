import AppKit

// MARK: - FolderNavigationBackButton

/// 标题区里的返回按钮：半透明白色圆角矩形，中间是向左的 chevron；悬停不变，按下时底色加深，在按钮上抬起才触发
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

    /// 画底色与 chevron
    override func draw(_: NSRect) {
        let opacity = isPressed
            ? FolderPanelMetrics.backButtonPressedOpacity
            : FolderPanelMetrics.backButtonOpacity
        let radius = FolderPanelMetrics.backButtonCornerRadius

        NSColor(white: 1, alpha: opacity).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        // chevron 的两条边与水平方向成 45°，宽度是高度的一半
        let height = FolderPanelMetrics.backChevronHeight
        let chevron = NSBezierPath()
        chevron.move(to: CGPoint(x: bounds.midX + height / 4, y: bounds.midY + height / 2))
        chevron.line(to: CGPoint(x: bounds.midX - height / 4, y: bounds.midY))
        chevron.line(to: CGPoint(x: bounds.midX + height / 4, y: bounds.midY - height / 2))
        chevron.lineWidth = Self.chevronLineWidth
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round

        NSColor.white.setStroke()
        chevron.stroke()
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
    /// 事件发生的位置是否在按钮内
    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }
}
