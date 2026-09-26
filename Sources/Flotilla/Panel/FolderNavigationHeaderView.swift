import AppKit

// MARK: - FolderNavigationHeaderView

/// 面板主体顶部的标题区：根层级与子层级都显示当前文件夹名，子层级另在左侧显示返回按钮
@MainActor
final class FolderNavigationHeaderView: NSView {
    /// 返回按钮；根层级没有
    private let backButton: FolderNavigationBackButton?

    /// 当前文件夹名
    private let titleField = FolderPanelLabel(labelWithString: "")

    /// 自上而下排列，与面板主体顶边的实测距离一致
    override var isFlipped: Bool {
        true
    }

    /// 创建标题区
    /// - Parameters:
    ///   - title: 当前文件夹名
    ///   - backHandler: 点击返回按钮后执行；为 nil 时不显示返回按钮
    init(title: String, backHandler: (() -> Void)?) {
        backButton = backHandler.map { FolderNavigationBackButton(clickHandler: $0) }

        super.init(frame: .zero)

        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: FolderPanelMetrics.headerTitleFontSize)
        titleField.textColor = .white
        titleField.alignment = .center
        titleField.usesSingleLineMode = true
        titleField.lineBreakMode = .byTruncatingTail

        addSubview(titleField)

        if let backButton {
            addSubview(backButton)
        }
    }

    /// 标题区完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 返回按钮按实测位置摆放；标题在整个标题区里水平居中、按基线定位，两侧让出返回按钮的位置
    override func layout() {
        super.layout()

        let buttonFrame = FolderPanelMetrics.backButtonFrame
        backButton?.frame = buttonFrame

        let inset = buttonFrame.maxX
        let titleHeight = titleField.intrinsicContentSize.height

        titleField.frame = CGRect(
            x: inset,
            y: 0,
            width: max(0, bounds.width - 2 * inset),
            height: titleHeight
        )

        titleField.frame.origin.y = FolderPanelMetrics.headerTitleBaselineY
            - titleField.firstBaselineOffsetFromTop
    }
}
