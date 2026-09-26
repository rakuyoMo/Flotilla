import AppKit
import os

// MARK: - AppDelegate

/// 应用生命周期、主菜单与 URL 事件分发
@MainActor
final class AppDelegate: NSObject {
    /// Flotilla 处理的 URL scheme，与 Info.plist 的 `CFBundleURLTypes` 一致
    private static let urlScheme = "flotilla"

    /// 应用生命周期与 URL 事件相关的日志
    private nonisolated static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "AppDelegate"
    )

    /// 状态栏图标与菜单；启动完成后创建
    private var statusBarController: StatusBarController?

    /// 让 Dock 上的 tile 与根文件夹保持一致；启动完成后创建
    private var dockTileSynchronizer: DockTileSynchronizer?

    /// 面板的展开、收起与切换；启动完成后创建
    private var dockFolderPresenter: DockFolderPresenter?

    /// 从 URL 中解析根文件夹 id，只接受 `flotilla://folder/<uuid>`
    static func folderID(from url: URL) -> UUID? {
        guard url.scheme == urlScheme, url.host() == "folder" else { return nil }

        // `pathComponents` 形如 `["/", "<uuid>"]`，多出的层级一律视为无法识别
        let components = url.pathComponents
        guard components.count == 2 else { return nil }

        return UUID(uuidString: components[1])
    }
}

// MARK: NSApplicationDelegate

extension AppDelegate: NSApplicationDelegate {
    /// 开始同步 Dock tile、监听 tile 的点击
    ///
    /// 被 stub 拉起时，AppKit 在 `applicationDidFinishLaunching` 之前就送来 URL，面板必须在此之前就绪
    func applicationWillFinishLaunching(_: Notification) {
        startDockIntegration()
    }

    /// 搭好主菜单与状态栏，把当前这份 App 注册为 `flotilla` scheme 的处理者
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = makeMainMenu()

        statusBarController = StatusBarController(
            settingsWindowController: SettingsWindowController()
        )

        registerAsURLHandler()
    }

    /// 把 `flotilla://folder/<uuid>` 交给面板处理；整个过程不激活 Flotilla
    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let folderID = Self.folderID(from: url) else {
                Self.logger.notice("忽略无法识别的 URL：\(url.absoluteString, privacy: .public)")
                continue
            }

            guard let dockFolderPresenter else {
                Self.logger.error("面板不可用，忽略 URL：\(url.absoluteString, privacy: .public)")
                continue
            }

            dockFolderPresenter.handleURLSignal(folderID: folderID)
        }
    }
}

// MARK: - Private

extension AppDelegate {
    /// 构建最小主菜单：App 菜单只有“退出”；“编辑”菜单让设置窗口里的文本框响应标准快捷键
    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.items = [
            NSMenuItem(
                title: "退出 Flotilla",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            ),
        ]

        // 主菜单的每一项只是子菜单的容器，App 菜单的标题由系统显示为 App 名称
        let mainMenu = NSMenu()
        for submenu in [appMenu, makeEditMenu()] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }

        return mainMenu
    }

    /// “编辑”菜单：撤销、重做、剪切、复制、粘贴、全选，动作沿响应链交给当前的文本框
    private func makeEditMenu() -> NSMenu {
        let redoItem = NSMenuItem(
            title: "重做",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        let editMenu = NSMenu(title: "编辑")
        editMenu.items = [
            NSMenuItem(
                title: "撤销",
                action: Selector(("undo:")),
                keyEquivalent: "z"
            ),
            redoItem,
            .separator(),
            NSMenuItem(
                title: "剪切",
                action: #selector(NSText.cut(_:)),
                keyEquivalent: "x"
            ),
            NSMenuItem(
                title: "复制",
                action: #selector(NSText.copy(_:)),
                keyEquivalent: "c"
            ),
            NSMenuItem(
                title: "粘贴",
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            ),
            NSMenuItem(
                title: "全选",
                action: #selector(NSText.selectAll(_:)),
                keyEquivalent: "a"
            ),
        ]

        return editMenu
    }

    /// 创建 stub 生成器，据此启动 Dock tile 同步器与面板；缺少 stub 可执行文件时 Dock 上不会有 tile，两者都不启动
    private func startDockIntegration() {
        let executableName = DockTileBundleBuilder.executableName

        // 打包脚本把 stub 可执行文件放在 Flotilla.app/Contents/MacOS 下
        guard let executableURL = Bundle.main.url(forAuxiliaryExecutable: executableName) else {
            Self.logger.error("找不到 \(executableName, privacy: .public)，无法生成 Dock tile")
            return
        }

        let builder = DockTileBundleBuilder(
            directory: DockTileBundleBuilder.defaultDirectory,
            executableURL: executableURL
        )

        startDockTileSynchronizer(builder: builder)

        let presenter = DockFolderPresenter(
            store: .shared,
            preferences: .shared,
            locator: DockTileLocator(builder: builder)
        )
        presenter.start()
        dockFolderPresenter = presenter
    }

    /// 创建并启动 Dock tile 同步器；无法读写 Dock 偏好时只记录日志
    private func startDockTileSynchronizer(builder: DockTileBundleBuilder) {
        guard
            let dockPreferences = DockPreferences(
                domainName: DockPreferences.dockDomain,
                backupDirectory: DockPreferences.defaultBackupDirectory
            )
        else {
            Self.logger.error("无法读写 Dock 偏好，无法生成 Dock tile")
            return
        }

        let synchronizer = DockTileSynchronizer(
            store: .shared,
            preferences: .shared,
            builder: builder,
            dockPreferences: dockPreferences
        )
        synchronizer.start()
        dockTileSynchronizer = synchronizer
    }

    /// 让当前这份 App 成为 `flotilla` scheme 的处理者：重新打包后 bundle 内容变了，Launch Services 的旧注册可能失效
    private func registerAsURLHandler() {
        NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpenURLsWithScheme: Self.urlScheme
        ) { error in
            guard let error else { return }

            Self.logger.error("注册 URL scheme 处理者失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
