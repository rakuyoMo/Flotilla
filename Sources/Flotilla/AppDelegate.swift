import AppKit
import os

// MARK: - AppDelegate

/// 应用生命周期、主菜单与 URL 事件分发
@MainActor
final class AppDelegate: NSObject {
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

    /// 让 Dock 与 ⌘Tab 里的 App 图标随系统深浅外观切换
    private let appIconController = AppIconController()
}

// MARK: NSApplicationDelegate

extension AppDelegate: NSApplicationDelegate {
    /// 开始同步 Dock tile、监听 tile 的点击
    ///
    /// 被 stub 拉起时，AppKit 在 `applicationDidFinishLaunching` 之前就送来 URL，面板必须在此之前就绪
    func applicationWillFinishLaunching(_: Notification) {
        startDockIntegration()
    }

    /// 搭好主菜单与状态栏，按系统外观设好 App 图标，把当前这份 App 注册为 `flotilla` scheme 的处理者
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = makeMainMenu()

        appIconController.start()

        statusBarController = StatusBarController(
            settingsWindowController: SettingsWindowController(
                dockTileSynchronizer: dockTileSynchronizer
            )
        )

        registerAsURLHandler()
    }

    /// 处理 stub 发来的请求：展开或收起面板交给面板处理，拖到 tile 上的 App 加入根文件夹；
    /// 整个过程不激活 Flotilla
    func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let request = DockTileRequest(url: url) else {
                Self.logger.notice("忽略无法识别的 URL：\(url.absoluteString, privacy: .public)")
                continue
            }

            switch request {
            case .toggleFolder(let folderID):
                guard let dockFolderPresenter else {
                    Self.logger.error("面板不可用，忽略 URL：\(url.absoluteString, privacy: .public)")
                    continue
                }

                dockFolderPresenter.handleURLSignal(folderID: folderID)

            // 只加入 App bundle，与从访达拖进设置窗口时的判断相同；同一次拖放重复送达时由 `addApps` 去重
            case .addApps(let folderID, let appURLs):
                // stub 只代表根文件夹，指向其它文件夹的 URL 一律忽略
                guard FolderStore.shared.rootFolders.contains(where: { $0.id == folderID }) else {
                    Self.logger.notice("忽略不存在的根文件夹：\(folderID.uuidString, privacy: .public)")
                    continue
                }

                let bundleURLs = appURLs.filter {
                    AppReference.isApplicationBundle($0)
                }

                FolderStore.shared.addApps(bundleURLs, to: folderID)
            }
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
                title: String(
                    localized: "mainMenu.quit",
                    comment: "App 菜单的“退出 Flotilla”"
                ),
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
            title: String(
                localized: "mainMenu.redo",
                comment: "“编辑”菜单的“重做”"
            ),
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]

        let editMenu = NSMenu(
            title: String(
                localized: "mainMenu.edit",
                comment: "主菜单里“编辑”菜单的标题"
            )
        )
        editMenu.items = [
            NSMenuItem(
                title: String(
                    localized: "mainMenu.undo",
                    comment: "“编辑”菜单的“撤销”"
                ),
                action: Selector(("undo:")),
                keyEquivalent: "z"
            ),
            redoItem,
            .separator(),
            NSMenuItem(
                title: String(
                    localized: "mainMenu.cut",
                    comment: "“编辑”菜单的“剪切”"
                ),
                action: #selector(NSText.cut(_:)),
                keyEquivalent: "x"
            ),
            NSMenuItem(
                title: String(
                    localized: "mainMenu.copy",
                    comment: "“编辑”菜单的“复制”"
                ),
                action: #selector(NSText.copy(_:)),
                keyEquivalent: "c"
            ),
            NSMenuItem(
                title: String(
                    localized: "mainMenu.paste",
                    comment: "“编辑”菜单的“粘贴”"
                ),
                action: #selector(NSText.paste(_:)),
                keyEquivalent: "v"
            ),
            NSMenuItem(
                title: String(
                    localized: "mainMenu.selectAll",
                    comment: "“编辑”菜单的“全选”"
                ),
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
            toOpenURLsWithScheme: DockTileRequest.urlScheme
        ) { error in
            guard let error else { return }

            Self.logger.error("注册 URL scheme 处理者失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}
