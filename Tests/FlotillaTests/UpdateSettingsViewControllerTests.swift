import AppKit
import Sparkle
import Testing

@testable import Flotilla

// MARK: - UpdateSettingsViewControllerTests

/// 更新控件必须真正写回 Sparkle，并在自动检查关闭后禁用依赖项；每种语言都要完整显示
@MainActor
final class UpdateSettingsViewControllerTests {
    /// 隔离的 App 包目录，Sparkle 以包标识区分持久化设置
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaUpdates-\(UUID().uuidString).app")

    /// 本用例专属的偏好域，防止修改真实 App 的更新计划
    private let identifier = "com.rakuyo.flotilla.tests.\(UUID().uuidString)"

    /// 测试包使用的设置存储，便于检查持久化结果
    private let defaults: UserDefaults

    /// 使用真实 Sparkle 属性和绑定，但不启动网络检查
    private let updater: SPUUpdater

    /// 把生产配置复制到临时包中，以隔离的标识创建更新器
    init() throws {
        _ = NSApplication.shared

        let contents = directory.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)

        // 使用真实默认值，防止测试与 App 的自动检查和安装策略各自演化
        var info = try PrivacyUsageDescriptionTests.infoPlist()
        info["CFBundleIdentifier"] = identifier

        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )

        try data.write(to: contents.appending(path: "Info.plist"))

        let bundle = try #require(Bundle(url: directory))
        defaults = try #require(UserDefaults(suiteName: identifier))

        updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: nil),
            delegate: nil
        )
    }

    /// 清理临时包与本用例写入的更新偏好
    deinit {
        UserDefaults(suiteName: identifier)?.removePersistentDomain(forName: identifier)
        try? FileManager.default.removeItem(at: directory)
    }

    /// 首次使用每天自动检查，但自动下载安装必须由用户主动开启
    @Test
    func defaultsRequireOptInForInstallation() throws {
        let controller = UpdateSettingsViewController(updater: updater)
        let controls = descendants(of: controller.view)
        let buttons = controls.compactMap { $0 as? NSButton }

        #expect(buttons.first { $0.title == "updates.automaticChecks" }?.state == .on)
        #expect(buttons.first { $0.title == "updates.automaticInstallation" }?.state == .off)
        #expect(controls.compactMap { $0 as? NSPopUpButton }.first?.selectedTag() == 86_400)

        #expect(controls.compactMap { $0 as? NSTextField }.contains {
            $0.stringValue == "updates.neverChecked"
        })
    }

    /// 点击自动安装会持久化，关闭自动检查时禁用频率和自动安装，再开启时保留安装选择
    @Test
    func togglesPersistAndDisableDependentControls() throws {
        let controller = UpdateSettingsViewController(updater: updater)
        let controls = descendants(of: controller.view)
        let buttons = controls.compactMap { $0 as? NSButton }
        let checks = try #require(buttons.first { $0.title == "updates.automaticChecks" })
        let installation = try #require(buttons.first { $0.title == "updates.automaticInstallation" })
        let interval = try #require(controls.compactMap { $0 as? NSPopUpButton }.first)

        installation.performClick(nil)

        #expect(updater.automaticallyDownloadsUpdates)
        #expect(defaults.bool(forKey: "SUAutomaticallyUpdate"))

        checks.performClick(nil)

        #expect(!updater.automaticallyChecksForUpdates)
        #expect(!defaults.bool(forKey: "SUEnableAutomaticChecks"))
        #expect(!installation.isEnabled)
        #expect(!interval.isEnabled)

        checks.performClick(nil)

        #expect(installation.isEnabled)
        #expect(installation.state == .on)
        #expect(interval.isEnabled)
    }

    /// 频率菜单的点击直接改变更新调度的秒数，更新器的外部改动也会同步到控件
    @Test
    func frequencyWritesSchedulerAndReflectsExternalChanges() throws {
        let controller = UpdateSettingsViewController(updater: updater)
        let interval = try #require(
            descendants(of: controller.view)
                .compactMap { $0 as? NSPopUpButton }
                .first
        )

        // 菜单执行动作会触发 Cocoa 绑定的写回，单纯 selectItem 只改变控件外观
        interval.menu?.performActionForItem(at: 2)

        #expect(updater.updateCheckInterval == 604_800)
        #expect(defaults.double(forKey: "SUScheduledCheckInterval") == 604_800)

        updater.updateCheckInterval = 3600

        #expect(interval.selectedTag() == 3600)
    }

    /// 窗口缩到最窄时，全部译文与日期按完整宽度显示，不越出更新区
    @Test(arguments: LocalizationTests.languages)
    func localizedControlsFitMinimumWidth(language: String) throws {
        let table = try LocalizationTests.table(for: language)
        let controller = UpdateSettingsViewController(updater: updater)
        let controls = descendants(of: controller.view).compactMap { $0 as? NSControl }

        // 测试进程读不到 .lproj，按键替换成每种语言的实际文字后测量布局
        for control in controls {
            if let popup = control as? NSPopUpButton {
                for item in popup.itemArray {
                    item.title = try #require(table[item.title])
                }
            } else if let button = control as? NSButton {
                button.title = try #require(table[button.title])
            } else {
                control.stringValue = try #require(table[control.stringValue])
            }
        }

        let width = SettingsWindowController.minimumContentSize.width
            - 2 * SettingsWindowController.contentInset

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        for control in controls {
            // AppKit 标签的透明边缘可超出对齐线，布局应按实际对齐矩形检查
            let frame = control.convert(
                control.alignmentRect(forFrame: control.bounds),
                to: controller.view
            )

            #expect(control.bounds.width >= control.intrinsicContentSize.width, "\(control) 被压窄")
            #expect(frame.minX >= 0, "\(control) 越出更新区左侧")
            #expect(frame.maxX <= width, "\(control) 越出更新区右侧")
        }
    }
}

// MARK: - Private

extension UpdateSettingsViewControllerTests {
    /// 取出实际显示的控件，使测试覆盖 AppKit 的绑定和布局
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap {
            [$0] + descendants(of: $0)
        }
    }
}
