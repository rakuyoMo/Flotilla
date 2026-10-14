import AppKit
import Sparkle

// MARK: - UpdateSettingsViewController

/// 更新设置：直接绑定 Sparkle 的持久化属性，使菜单、更新弹窗与设置保持一致
@MainActor
final class UpdateSettingsViewController: NSViewController {
    /// 主菜单共用的更新器，负责检查计划与安装流程
    private let updater: SPUUpdater

    /// 最近检查时间的观察者，随视图控制器存活并刷新显示文字
    private var lastCheckObservation: NSKeyValueObservation?

    /// 创建与主菜单共享更新器的设置区
    /// - Parameter updater: App 生命周期内持续持有的更新器
    init(updater: SPUUpdater) {
        self.updater = updater

        super.init(nibName: nil, bundle: nil)
    }

    /// 更新区完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("不支持从归档解码")
    }

    /// 依次显示自动检查、自动安装、频率，以及上次检查时间和手动入口
    override func loadView() {
        let title = NSTextField(labelWithString: String(
            localized: "updates.sectionTitle",
            comment: "设置窗口更新区的标题"
        ))
        title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let automaticChecks = NSButton(
            checkboxWithTitle: String(
                localized: "updates.automaticChecks",
                comment: "自动检查更新的开关"
            ),
            target: nil,
            action: nil
        )

        automaticChecks.bind(
            .value,
            to: updater,
            withKeyPath: #keyPath(SPUUpdater.automaticallyChecksForUpdates),
            options: nil
        )

        let automaticInstallation = NSButton(
            checkboxWithTitle: String(
                localized: "updates.automaticInstallation",
                comment: "自动下载更新并在退出 App 时安装的开关"
            ),
            target: nil,
            action: nil
        )

        // Sparkle 同时处理后台下载与退出时安装；自动检查关闭时禁用此选项
        automaticInstallation.bind(
            .value,
            to: updater,
            withKeyPath: #keyPath(SPUUpdater.automaticallyDownloadsUpdates),
            options: nil
        )

        automaticInstallation.bind(
            .enabled,
            to: updater,
            withKeyPath: #keyPath(SPUUpdater.allowsAutomaticUpdates),
            options: nil
        )

        let stack = NSStackView(views: [
            title,
            automaticChecks,
            automaticInstallation,
            makeCheckDetails(),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8

        view = stack
    }
}

// MARK: - Private

extension UpdateSettingsViewController {
    /// 频率与最近检查时间按两列对齐，手动入口跟随更新器的忙碌状态
    private func makeCheckDetails() -> NSView {
        let interval = NSPopUpButton()

        let choices: [(String, Int)] = [
            (String(localized: "updates.hourly", comment: "每小时检查一次更新"), 60 * 60),
            (String(localized: "updates.daily", comment: "每天检查一次更新"), 24 * 60 * 60),
            (String(localized: "updates.weekly", comment: "每周检查一次更新"), 7 * 24 * 60 * 60),
        ]

        // 选项的 tag 使用秒数，与 Sparkle 调度器的持久化频率保持一致
        for (title, seconds) in choices {
            interval.addItem(withTitle: title)
            interval.lastItem?.tag = seconds
        }

        interval.bind(
            .selectedTag,
            to: updater,
            withKeyPath: #keyPath(SPUUpdater.updateCheckInterval),
            options: nil
        )

        interval.bind(
            .enabled,
            to: updater,
            withKeyPath: #keyPath(SPUUpdater.automaticallyChecksForUpdates),
            options: nil
        )

        let checkButton = NSButton(
            title: String(
                localized: "updates.checkForUpdates",
                comment: "App 菜单与设置里的手动检查更新入口"
            ),
            target: updater,
            action: #selector(SPUUpdater.checkForUpdates)
        )

        checkButton.bind(
            .enabled,
            to: updater,
            withKeyPath: #keyPath(SPUUpdater.canCheckForUpdates),
            options: nil
        )

        let lastCheck = NSTextField(labelWithString: "")

        // 时间由 Sparkle 的检查结果驱动；首次检查之前用本地化占位文字表示
        lastCheckObservation = updater.observe(
            \.lastUpdateCheckDate,
            options: [.initial, .new]
        ) { _, change in
            // Sparkle 的属性只在主线程更新，观察回调与 AppKit 控件处于同一执行域
            MainActor.assumeIsolated {
                lastCheck.stringValue =
                    if let date = change.newValue ?? nil {
                        date.formatted(date: .abbreviated, time: .shortened)
                    } else {
                        String(
                            localized: "updates.neverChecked",
                            comment: "尚未检查过更新时显示的占位文字"
                        )
                    }
            }
        }

        let grid = NSGridView(views: [
            [
                NSTextField(labelWithString: String(
                    localized: "updates.checkFrequency",
                    comment: "自动检查频率的标签"
                )),
                NSStackView(views: [interval, checkButton]),
            ],
            [
                NSTextField(labelWithString: String(
                    localized: "updates.lastCheck",
                    comment: "上次检查更新时间的标签"
                )),
                lastCheck,
            ],
        ])

        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8

        return grid
    }
}
