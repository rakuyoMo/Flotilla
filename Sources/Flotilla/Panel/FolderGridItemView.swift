import AppKit

// MARK: - FolderGridItemView

/// 网格中的一个单元格：图标在上、名称在下；悬停没有任何变化，按下时图标变暗，在同一格上抬起才触发
@MainActor
final class FolderGridItemView: NSView {
    /// 图标
    private let imageView = NSImageView()

    /// 名称
    private let titleField = FolderPanelLabel(labelWithString: "")

    /// 平常显示的图标
    private let icon: NSImage

    /// 按下时显示的图标，第一次按下时生成
    private lazy var pressedIcon = Self.darkened(icon)

    /// 点击后执行的动作
    private let clickHandler: () -> Void

    /// 是否处于按下状态：按下后拖出单元格即恢复，拖回来再次按下
    private var isPressed = false {
        didSet {
            imageView.image = isPressed ? pressedIcon : icon
        }
    }

    /// 自上而下排列，与单元格 frame 的坐标系一致
    override var isFlipped: Bool {
        true
    }

    /// 图标中心，自身坐标系；进入子文件夹时新层级从这里长出来
    var iconCenter: CGPoint {
        CGPoint(x: bounds.midX, y: FolderPanelMetrics.iconCenterY)
    }

    /// 创建单元格
    /// - Parameters:
    ///   - title: 名称
    ///   - icon: 图标
    ///   - clickHandler: 在单元格内按下并抬起后执行
    init(title: String, icon: NSImage, clickHandler: @escaping () -> Void) {
        self.icon = icon
        self.clickHandler = clickHandler

        super.init(frame: .zero)

        imageView.image = icon
        imageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(imageView)

        // 名称只显示一行，过长时在中间省略
        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: FolderPanelMetrics.titleFontSize)
        titleField.textColor = .white
        titleField.alignment = .center
        titleField.usesSingleLineMode = true
        titleField.lineBreakMode = .byTruncatingMiddle
        addSubview(titleField)
    }

    /// 单元格完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 图标按中心定位；名称水平居中，按基线定位
    override func layout() {
        super.layout()

        let iconSize = FolderPanelMetrics.iconSize
        imageView.frame = CGRect(
            x: iconCenter.x - iconSize / 2,
            y: iconCenter.y - iconSize / 2,
            width: iconSize,
            height: iconSize
        )

        // 文本框在文字两侧各留有内边距，frame 要比文字的最大宽度宽出这部分
        let titleWidth = FolderPanelMetrics.titleMaximumWidth + 2 * Self.titlePadding
        let titleHeight = titleField.intrinsicContentSize.height
        titleField.frame = CGRect(
            x: (bounds.width - titleWidth) / 2,
            y: 0,
            width: titleWidth,
            height: titleHeight
        )

        titleField.frame.origin.y = FolderPanelMetrics.titleBaselineY - titleField.firstBaselineOffsetFromTop
    }

    /// 整个单元格作为一个点击目标，图标与名称不单独响应鼠标
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    /// 面板不是 key window 时，第一次点击也直接生效
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
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

// MARK: - Helpers

extension FolderGridItemView {
    /// `NSTextField` 在文字两侧留出的内边距
    private static let titlePadding: CGFloat = 2

    /// 把图标的颜色乘以按下时的亮度，透明部分保持透明
    private static func darkened(_ icon: NSImage) -> NSImage {
        NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)

            NSColor(white: 0, alpha: 1 - FolderPanelMetrics.pressedIconBrightness).setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}
