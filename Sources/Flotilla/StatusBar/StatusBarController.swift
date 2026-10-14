import AppKit

// MARK: - StatusBarController

/// 状态栏图标与菜单（需求 7）
@MainActor
final class StatusBarController: NSObject {
    /// 状态栏图标；释放后会从状态栏消失，因此由本对象持有
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    /// 菜单 “设置…” 打开的设置窗口
    private let settingsWindowController: SettingsWindowController

    /// 创建状态栏图标并挂上菜单
    /// - Parameter settingsWindowController: 菜单 “设置…” 打开的设置窗口
    init(settingsWindowController: SettingsWindowController) {
        self.settingsWindowController = settingsWindowController
        super.init()

        statusItem.button?.image = StatusBarIcon.makeImage()
        statusItem.menu = makeMenu()
    }
}

// MARK: - Private

extension StatusBarController {
    /// 菜单：“设置…”、分隔线、“退出归帆”
    private func makeMenu() -> NSMenu {
        let settingsItem = NSMenuItem(
            title: String(
                localized: "settings.menuTitle",
                comment: "App 名称菜单与状态栏菜单共用的 “设置…” 入口"
            ),
            action: #selector(SettingsWindowController.show),
            keyEquivalent: ","
        )

        // 状态栏入口与 App 菜单指向同一窗口，控制器由本对象持续持有
        settingsItem.target = settingsWindowController

        let menu = NSMenu()
        menu.items = [
            settingsItem,
            .separator(),
            NSMenuItem(
                title: String(
                    localized: "mainMenu.quit",
                    comment: "状态栏菜单的 “退出归帆”，与 App 菜单的同名项共用"
                ),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            ),
        ]

        return menu
    }
}
