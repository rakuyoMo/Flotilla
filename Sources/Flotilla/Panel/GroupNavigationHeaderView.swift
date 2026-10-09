import AppKit

// MARK: - GroupNavigationHeaderView

/// 面板主体顶部的标题区：根层级与子层级都显示当前文件夹名，子层级另在左侧显示返回按钮
@MainActor
final class GroupNavigationHeaderView: NSView {
    /// 返回按钮；根层级没有
    private let backButton: GroupNavigationBackButton?

    /// 当前层级的名称
    private let titleField = GroupPanelLabel(labelWithString: "")

    /// 自上而下排列，与面板主体顶边的实测距离一致
    override var isFlipped: Bool {
        true
    }

    /// 创建标题区
    /// - Parameters:
    ///   - title: 当前层级的名称：文件夹名，或访达里的文件夹在访达中显示的名称
    ///   - backHandler: 点击返回按钮后执行；为 nil 时不显示返回按钮
    init(title: String, backHandler: (() -> Void)?) {
        backButton = backHandler.map { GroupNavigationBackButton(clickHandler: $0) }

        super.init(frame: .zero)

        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: GroupPanelMetrics.headerTitleFontSize)
        titleField.textColor = GroupPanelAppearance.dynamicTextColor
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
        fatalError("不支持从归档解码")
    }

    /// 返回按钮按实测位置摆放；标题按原生的取整方式水平居中、按基线定位，两侧让出返回按钮的位置
    override func layout() {
        super.layout()

        let buttonFrame = GroupPanelMetrics.backButtonFrame
        backButton?.frame = buttonFrame

        let inset = buttonFrame.maxX
        let titleHeight = titleField.intrinsicContentSize.height

        // 标题框两侧等宽、按原生标题中心平移，文字在框里居中，即落在原生的位置
        titleField.frame = CGRect(
            x: inset + nativeTitleCenterOffset(),
            y: 0,
            width: max(0, bounds.width - 2 * inset),
            height: titleHeight
        )

        titleField.frame.origin.y = GroupPanelMetrics.headerTitleBaselineY
            - titleField.firstBaselineOffsetFromTop
    }

    /// 原生标题中心相对标题区中心的水平偏移：0 或 −0.5 pt
    ///
    /// 原生标题框宽为文字宽向上取整再加 1 pt，左边是居中位置向下取整到点，文字在框里居中；
    /// 框宽为奇数时标题中心因此比标题区中心偏左 0.5 pt（原生屏上实测）
    private func nativeTitleCenterOffset() -> CGFloat {
        let textWidth = titleField.attributedStringValue.size().width

        // 原生标题框的宽与左边
        let frameWidth = textWidth.rounded(.up) + GroupPanelMetrics.headerTitleFrameExtraWidth
        let frameX = ((bounds.width - frameWidth) / 2).rounded(.down)

        return frameX + frameWidth / 2 - bounds.width / 2
    }
}
