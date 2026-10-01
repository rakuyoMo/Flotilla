import AppKit
import Testing

@testable import Flotilla

// MARK: - GeneralSettingsViewControllerTests

/// 设置窗口的通用区：显示隐藏文件的复选框要反映当前的设置、点了要写回，否则面板展开访达里的文件夹时与用户看到的不符；
/// 窗口缩到最窄时，每种语言的各行都完整显示
@MainActor
final class GeneralSettingsViewControllerTests {
    /// 设置窗口缩到最窄时通用区可用的宽度：内容区最小宽度扣除左右边距
    private static let minimumWidth = SettingsWindowController.minimumContentSize.width
        - 2 * SettingsWindowController.contentInset

    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例独占的 `UserDefaults`
    private let defaults: UserDefaults

    /// 以临时目录下的绝对路径作 suite 名称，设置写进该目录的 plist，不碰真实的偏好设置
    init() throws {
        let suiteName = directory.appending(path: "defaults").path(percentEncoded: false)
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 复选框显示当前的设置；点击后写回，再点一次写回原值
    @Test
    func checkboxReflectsAndWritesShowsHiddenFiles() throws {
        let preferences = Preferences(defaults: defaults)
        preferences.showsHiddenFiles = true

        let controller = GeneralSettingsViewController(preferences: preferences)

        let checkbox = try #require(
            descendants(of: controller.view)
                .compactMap { $0 as? NSButton }
                .first { $0.title == "general.showHiddenFiles" }
        )

        #expect(checkbox.state == .on)

        checkbox.performClick(nil)

        #expect(checkbox.state == .off)
        #expect(!preferences.showsHiddenFiles)

        checkbox.performClick(nil)

        #expect(preferences.showsHiddenFiles)
    }

    /// 窗口缩到最窄时，每种语言的标签、复选框与按钮都按完整文字的宽度排开，不越出通用区
    @Test(arguments: LocalizationTests.languages)
    func rowsFitMinimumWidth(language: String) throws {
        let table = try LocalizationTests.table(for: language)
        let controller = GeneralSettingsViewController(preferences: Preferences(defaults: defaults))

        let controls = descendants(of: controller.view).compactMap { $0 as? NSControl }

        // 测试进程读不到 `.lproj` 里的译文，文字就是键名，按键名换成这种语言的文字；选择器的选项是数字，不用换
        for control in controls where !(control is NSPopUpButton) {
            if let button = control as? NSButton {
                button.title = try #require(table[button.title], "表里没有 \(button.title)")
            } else {
                control.stringValue = try #require(table[control.stringValue], "表里没有 \(control.stringValue)")
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.minimumWidth, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        window.contentView = controller.view
        controller.view.layoutSubtreeIfNeeded()

        // 每个控件都不窄于完整文字需要的宽度，最右边不越出通用区
        for control in controls {
            let frame = control.convert(control.bounds, to: controller.view)

            #expect(frame.width >= control.intrinsicContentSize.width, "\(control) 被压窄")
            #expect(frame.maxX <= Self.minimumWidth, "\(control) 越出通用区")
        }
    }
}

// MARK: - Private

extension GeneralSettingsViewControllerTests {
    /// 视图的全部子孙视图，深度优先
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap {
            [$0] + descendants(of: $0)
        }
    }
}
