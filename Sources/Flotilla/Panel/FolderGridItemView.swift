import AppKit

// MARK: - FolderGridItemView

/// 网格中的一个单元格：图标在上、名称在下；悬停没有任何变化，按下与抬起的表现见 `FolderGridItemStyle`
@MainActor
final class FolderGridItemView: NSView {
    /// 图标
    private let imageView = NSImageView()

    /// 名称
    private let titleField = FolderPanelLabel(labelWithString: "")

    /// 样式
    private let style: FolderGridItemStyle

    /// 图标：各项原样显示，子文件夹的图标在系统外观变化时由网格换成对应外观的版本；
    /// “在访达中打开”只取原图的形状，按外观着色后显示
    var icon: NSImage {
        didSet {
            // 平常与按下时的图都跟着换，正在按下时也立即显示新的
            refreshImages()
        }
    }

    /// 平常显示的图：由图标按样式生成
    private lazy var normalImage = makeImage(isPressed: false)

    /// 按下时显示的图：第一次按下时生成；
    /// 图标或外观变化时与平常的图一起重新生成
    private lazy var pressedImage = makeImage(isPressed: true)

    /// 点击后执行的动作
    private let clickHandler: () -> Void

    /// 是否处于按下状态：各项拖出单元格即恢复、拖回来再次按下，“在访达中打开”保持到抬起
    private var isPressed = false {
        didSet {
            imageView.image = isPressed ? pressedImage : normalImage
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
    ///   - icon: 图标；“在访达中打开”是透明底上的原图，只取形状
    ///   - style: 样式，默认是各项的样式
    ///   - clickHandler: 按下并抬起后执行，在哪里抬起才算见 `FolderGridItemStyle`
    init(
        title: String,
        icon: NSImage,
        style: FolderGridItemStyle = .item,
        clickHandler: @escaping () -> Void
    ) {
        self.icon = icon
        self.style = style
        self.clickHandler = clickHandler

        super.init(frame: .zero)

        imageView.imageScaling = .scaleProportionallyUpOrDown

        // “在访达中打开”的图标自成一层，按外观的合成方式与下面的面板材质合成
        if style == .openInFinder {
            #warning("TODO: 未能实测 macOS 15 behind-window 的 popover 材质上叠加是否生效（本机 macOS 27 用的是玻璃）")

            imageView.wantsLayer = true
            imageView.layer?.compositingFilter = panelAppearance.openInFinderCompositingFilter
        }

        imageView.image = normalImage

        addSubview(imageView)

        // 名称只显示一行，过长时在中间省略
        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: FolderPanelMetrics.titleFontSize)
        titleField.textColor = FolderPanelAppearance.dynamicTextColor
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

        // “在访达中打开”的原图比其它图标画得小一些
        let iconSize =
            switch style {
            case .item:
                FolderPanelMetrics.iconSize

            case .openInFinder:
                FolderPanelMetrics.openInFinderIconSize
            }

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

        titleField.frame.origin.y = FolderPanelMetrics.titleBaselineY
            - titleField.firstBaselineOffsetFromTop
    }

    /// 整个单元格作为一个点击目标，图标与名称不单独响应鼠标
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    /// 面板不是 key window 时，第一次点击也直接生效
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    /// 系统外观变化时，“在访达中打开”换成对应外观的颜色与合成方式；各项的图标由网格负责
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()

        guard style == .openInFinder else { return }

        imageView.layer?.compositingFilter = panelAppearance.openInFinderCompositingFilter
        refreshImages()
    }

    /// 按下：进入按下状态
    override func mouseDown(with _: NSEvent) {
        isPressed = true
    }

    /// 拖动：各项只在鼠标仍位于单元格内时保持按下状态；“在访达中打开”一直保持到抬起
    override func mouseDragged(with event: NSEvent) {
        guard style == .item else { return }

        isPressed = contains(event)
    }

    /// 抬起：各项在单元格内抬起才算一次点击；“在访达中打开”拖出单元格、拖出面板再抬起也算
    override func mouseUp(with event: NSEvent) {
        isPressed = false

        guard style == .openInFinder || contains(event) else { return }

        clickHandler()
    }
}

// MARK: - Private

extension FolderGridItemView {
    /// 单元格当前外观对应的面板取值
    private var panelAppearance: FolderPanelAppearance {
        FolderPanelAppearance(effectiveAppearance)
    }

    /// 事件发生的位置是否在单元格内
    private func contains(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }

    /// 平常或按下时显示的图：各项平常就是图标、按下时压暗；“在访达中打开”按外观着色
    private func makeImage(isPressed: Bool) -> NSImage {
        switch style {
        case .item:
            isPressed ? Self.darkened(icon) : icon

        case .openInFinder:
            Self.tinted(
                icon,
                color: panelAppearance.openInFinderIconColor(isPressed: isPressed)
            )
        }
    }

    /// 重新生成平常与按下时的图，并显示当前状态的那张
    private func refreshImages() {
        normalImage = makeImage(isPressed: false)
        pressedImage = makeImage(isPressed: true)
        imageView.image = isPressed ? pressedImage : normalImage
    }
}

// MARK: - Helpers

extension FolderGridItemView {
    /// `NSTextField` 在文字两侧留出的内边距
    private static let titlePadding: CGFloat = 2

    /// 着色时原图的像素边长：Dock 的 `openinfinder.png` 是 128 pt，2 倍图 256 px
    private static let glyphPixelSide = 256

    /// 把图标的颜色乘以按下时的亮度，透明部分保持透明
    private static func darkened(_ icon: NSImage) -> NSImage {
        NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)

            NSColor(white: 0, alpha: 1 - FolderPanelMetrics.pressedIconBrightness).setFill()
            rect.fill(using: .sourceAtop)

            return true
        }
    }

    /// 在原图 2 倍图的分辨率上，只给原图不透明的地方铺上颜色，得到 `openInFinderIconSize` 大小的图
    ///
    /// 着色时不缩放，显示时由 Core Animation 线性插值缩到屏上的像素，边缘与原生一致；
    /// 着色时先缩放再显示，边缘的抗锯齿与原生差出十几个灰阶
    private static func tinted(_ glyph: NSImage, color: NSColor) -> NSImage {
        let side = CGFloat(glyphPixelSide)
        let rect = CGRect(x: 0, y: 0, width: side, height: side)

        let context = CGContext(
            data: nil,
            width: glyphPixelSide,
            height: glyphPixelSide,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        guard let context else { return glyph }

        // 按 1 倍绘制 256 pt，原图挑中 256 px 的 2 倍图，一比一画上，再只在不透明的地方铺颜色
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        glyph.draw(in: rect)

        color.setFill()
        rect.fill(using: .sourceIn)

        NSGraphicsContext.restoreGraphicsState()

        guard let image = context.makeImage() else { return glyph }

        let size = FolderPanelMetrics.openInFinderIconSize

        return NSImage(cgImage: image, size: CGSize(width: size, height: size))
    }
}
