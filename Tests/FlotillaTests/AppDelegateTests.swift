import AppKit
import Testing

@testable import Flotilla

// MARK: - AppDelegateTests

/// App 菜单入口与单实例保护：App 菜单能打开 “关于” 和共用的设置窗口；
/// 两个 Flotilla 会同时改写 Dock 偏好，启动时发现别的实例就必须退出；
/// 同一 bundle id 的实例列表里总有当前进程自己，它不能被当成 “别的实例”，否则 Flotilla 永远起不来
@MainActor
struct AppDelegateTests {
    /// 假定的当前进程号；
    /// 测试参数里的 200 就是当前进程自己
    private let currentProcessIdentifier: pid_t = 200

    /// “关于” 与 “设置…” 位于 App 名称菜单，设置入口指向共用窗口并支持 ⌘,
    @Test
    func appMenuProvidesAboutAndSharedSettings() throws {
        _ = NSApplication.shared

        let delegate = AppDelegate()
        let settingsWindowController = SettingsWindowController(dockTileSynchronizer: nil)
        let mainMenu = delegate.makeMainMenu(settingsWindowController: settingsWindowController)
        let appMenu = try #require(mainMenu.items.first?.submenu)

        // 菜单目标是弱引用，检查时保持 App 生命周期对象存活
        try withExtendedLifetime(delegate) {
            let aboutItem = try #require(appMenu.items.first {
                $0.target is AboutPanelController
            })

            #expect(aboutItem.action == #selector(AboutPanelController.show))

            let settingsItem = try #require(appMenu.items.first {
                $0.target === settingsWindowController
            })

            #expect(settingsItem.action == #selector(SettingsWindowController.show))
            #expect(settingsItem.keyEquivalent == ",")
            #expect(settingsItem.keyEquivalentModifierMask == .command)
        }
    }

    /// 只有当前进程在运行：不是重复启动
    @Test
    func aloneIsNotDuplicate() {
        let other = AppDelegate.otherInstance(
            among: [currentProcessIdentifier],
            currentProcessIdentifier: currentProcessIdentifier
        ) { $0 }

        #expect(other == nil)
    }

    /// 另有一个实例在运行，不论它在列表里排在当前进程之前还是之后，都要找出它
    @Test(arguments: [
        [pid_t(100), 200],
        [200, 300],
    ])
    func findsOtherInstance(instances: [pid_t]) {
        let other = AppDelegate.otherInstance(
            among: instances,
            currentProcessIdentifier: currentProcessIdentifier
        ) { $0 }

        #expect(other != nil)
        #expect(other != currentProcessIdentifier)
    }
}
