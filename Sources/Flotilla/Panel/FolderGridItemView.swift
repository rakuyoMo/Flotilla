import AppKit

// MARK: - FolderGridItemView

/// 网格中的一个单元格：图标在上、名称在下；悬停时显示圆角高亮，按下时颜色更深，抬起时触发点击
@MainActor
final class FolderGridItemView: NSView {
    #warning("TODO: 待实测 图标 64、图标与名称间距 4、名称 12 pt 最多 2 行、高亮圆角 8 与悬停、按下的颜色")

    /// 图标
    private let imageView = NSImageView()

    /// 名称
    private let titleField = NSTextField(wrappingLabelWithString: "")

    /// 点击后执行的动作
    private let clickHandler: () -> Void

    /// 鼠标是否悬停在单元格上
    private var isHovered = false {
        didSet {
            needsDisplay = true
        }
    }

    /// 是否处于按下状态：按下后拖出单元格即恢复，拖回来再次按下
    private var isPressed = false {
        didSet {
            needsDisplay = true
        }
    }

    /// 自上而下排列，与单元格 frame 的坐标系一致
    override var isFlipped: Bool {
        true
    }

    /// 创建单元格
    /// - Parameters:
    ///   - title: 名称
    ///   - icon: 图标
    ///   - clickHandler: 在单元格内按下并抬起后执行
    init(title: String, icon: NSImage, clickHandler: @escaping () -> Void) {
        self.clickHandler = clickHandler

        super.init(frame: .zero)

        imageView.image = icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        // 名称居中，最多两行，放不下时在最后一行末尾省略
        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: FolderPanelMetrics.titleFontSize)
        titleField.alignment = .center
        titleField.maximumNumberOfLines = FolderPanelMetrics.titleMaximumLines
        titleField.lineBreakMode = .byWordWrapping
        titleField.cell?.truncatesLastVisibleLine = true
        addSubview(titleField)

        // 面板所在的 App 始终不在前台，悬停追踪要在任何状态下都生效
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    /// 单元格完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 图标水平居中；图标、间距与两行名称作为一个整体在单元格内竖直居中，名称不足两行时图标位置不变
    override func layout() {
        super.layout()

        let iconSize = FolderPanelMetrics.iconSize
        let spacing = FolderPanelMetrics.iconTitleSpacing
        let lineHeight = titleField.font.map { ceil($0.ascender - $0.descender + $0.leading) } ?? 0
        let titleHeight = lineHeight * CGFloat(FolderPanelMetrics.titleMaximumLines)

        let top = max(0, (bounds.height - iconSize - spacing - titleHeight) / 2)
        imageView.frame = CGRect(
            x: (bounds.width - iconSize) / 2,
            y: top,
            width: iconSize,
            height: iconSize
        )

        let titleTop = imageView.frame.maxY + spacing
        titleField.frame = CGRect(
            x: 0,
            y: titleTop,
            width: bounds.width,
            height: max(0, bounds.height - titleTop)
        )
    }

    /// 悬停时画浅色圆角高亮，按下时画深色
    override func draw(_: NSRect) {
        guard isHovered || isPressed else { return }

        let color: NSColor = isPressed ? .tertiaryLabelColor : .quaternaryLabelColor
        color.setFill()

        let radius = FolderPanelMetrics.highlightCornerRadius
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
    }

    /// 面板不是 key window 时，第一次点击也直接生效
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    /// 鼠标进入单元格
    override func mouseEntered(with _: NSEvent) {
        isHovered = true
    }

    /// 鼠标离开单元格
    override func mouseExited(with _: NSEvent) {
        isHovered = false
    }

    /// 按下：进入按下状态
    override func mouseDown(with _: NSEvent) {
        isPressed = true
    }

    /// 拖动：只在鼠标仍位于单元格内时保持按下状态
    override func mouseDragged(with event: NSEvent) {
        isPressed = contains(event)
    }

    /// 抬起：鼠标仍位于单元格内才算一次点击
    override func mouseUp(with event: NSEvent) {
        isPressed = false

        guard contains(event) else { return }

        clickHandler()
    }
}

// MARK: - Private

extension FolderGridItemView {
    /// 事件发生的位置是否在单元格内
    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }
}
