import AppKit
import ApplicationServices

// MARK: - GeneralSettingsViewController

/// 设置窗口的通用区：预览图标数，以及辅助功能权限的授权状态
@MainActor
final class GeneralSettingsViewController: NSViewController {
    /// 系统设置里辅助功能权限页的地址
    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    /// 用户设置
    private let preferences: Preferences

    /// 预览图标数的选择器，选项 0–4，第 n 项即数量 n
    private let previewIconCountPopUp = NSPopUpButton()

    /// 辅助功能权限的授权状态
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")

    /// 创建通用区
    /// - Parameter preferences: 用户设置
    init(preferences: Preferences) {
        self.preferences = preferences

        super.init(nibName: nil, bundle: nil)
    }

    /// 通用区完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 区块标题与两行设置项自上而下排列
    override func loadView() {
        let counts = 0 ... Preferences.maximumPreviewIconCount
        previewIconCountPopUp.addItems(withTitles: counts.map { String($0) })
        previewIconCountPopUp.selectItem(at: preferences.previewIconCount)
        previewIconCountPopUp.target = self
        previewIconCountPopUp.action = #selector(previewIconCountChanged)

        let openSettingsButton = NSButton(
            title: String(
                localized: "general.openSystemSettings",
                comment: "打开系统设置辅助功能权限页的按钮"
            ),
            target: self,
            action: #selector(openAccessibilitySettings)
        )

        let accessibilityRow = NSStackView(views: [accessibilityStatusLabel, openSettingsButton])

        let previewIconCountLabel = NSTextField(
            labelWithString: String(
                localized: "general.previewIconCount",
                comment: "预览图标数选择器左侧的标签：Dock 上的文件夹图标里最多显示几个 App 图标"
            )
        )

        let accessibilityLabel = NSTextField(
            labelWithString: String(
                localized: "general.accessibility",
                comment: "辅助功能权限一行左侧的标签"
            )
        )

        // 两列网格：左列标签右对齐，右列控件左对齐，各行按首行基线对齐
        let gridView = NSGridView(views: [
            [previewIconCountLabel, previewIconCountPopUp],
            [accessibilityLabel, accessibilityRow],
        ])

        gridView.column(at: 0).xPlacement = .trailing
        gridView.rowAlignment = .firstBaseline
        gridView.rowSpacing = 12

        let titleLabel = NSTextField(
            labelWithString: String(
                localized: "general.sectionTitle",
                comment: "设置窗口通用区的区块标题"
            )
        )
        titleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let stackView = NSStackView(views: [titleLabel, gridView])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 8

        view = stackView
        refreshAccessibilityStatus()
    }

    /// 按 `AXIsProcessTrusted()` 刷新辅助功能权限的显示
    func refreshAccessibilityStatus() {
        accessibilityStatusLabel.stringValue =
            if AXIsProcessTrusted() {
                String(
                    localized: "general.accessibilityGranted",
                    comment: "辅助功能权限的状态：已授权"
                )
            } else {
                String(
                    localized: "general.accessibilityNotGranted",
                    comment: "辅助功能权限的状态：未授权"
                )
            }
    }
}

// MARK: - Actions

extension GeneralSettingsViewController {
    /// 选择器变化时写回预览图标数
    @objc
    private func previewIconCountChanged() {
        preferences.previewIconCount = previewIconCountPopUp.indexOfSelectedItem
    }

    /// 打开系统设置的辅助功能权限页
    @objc
    private func openAccessibilitySettings() {
        guard let url = Self.accessibilitySettingsURL else { return }

        NSWorkspace.shared.open(url)
    }
}
