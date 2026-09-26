import AppKit

// MARK: - FolderNavigationHeaderView

/// 子文件夹层级顶部的导航头：左侧返回按钮，中间是当前文件夹名
@MainActor
final class FolderNavigationHeaderView: NSView {
    #warning("TODO: 待实测 返回按钮的样式、尺寸与位置，标题字号与字重")

    /// 返回按钮
    private let backButton = FolderNavigationBackButton()

    /// 当前文件夹名
    private let titleField = NSTextField(labelWithString: "")

    /// 点击返回按钮后执行的动作
    private let backHandler: () -> Void

    /// 创建导航头
    /// - Parameters:
    ///   - title: 当前文件夹名
    ///   - backHandler: 点击返回按钮后执行
    init(title: String, backHandler: @escaping () -> Void) {
        self.backHandler = backHandler

        super.init(frame: .zero)

        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "返回")
        backButton.imagePosition = .imageOnly
        backButton.isBordered = false
        backButton.target = self
        backButton.action = #selector(goBack)
        addSubview(backButton)

        titleField.stringValue = title
        titleField.font = .boldSystemFont(ofSize: FolderPanelMetrics.headerTitleFontSize)
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        addSubview(titleField)
    }

    /// 导航头完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 返回按钮贴左侧竖直居中；标题两侧各让出一个按钮宽度，保证在整个导航头里居中
    override func layout() {
        super.layout()

        let buttonSize = FolderPanelMetrics.backButtonSize
        backButton.frame = CGRect(
            x: 0,
            y: (bounds.height - buttonSize) / 2,
            width: buttonSize,
            height: buttonSize
        )

        let titleHeight = titleField.intrinsicContentSize.height
        titleField.frame = CGRect(
            x: buttonSize,
            y: (bounds.height - titleHeight) / 2,
            width: max(0, bounds.width - 2 * buttonSize),
            height: titleHeight
        )
    }
}

// MARK: - Actions

extension FolderNavigationHeaderView {
    /// 点击返回按钮
    @objc
    private func goBack() {
        backHandler()
    }
}
