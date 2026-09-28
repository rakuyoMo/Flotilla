import AppKit

// MARK: - SettingsWindowController

/// 设置窗口：显示时让 Flotilla 出现在 Dock 与前台；关闭后只隐藏，若没有其它可见窗口就回到无 Dock 图标的状态
@MainActor
final class SettingsWindowController: NSWindowController {
    /// 文件夹区
    private let folderTreeViewController: FolderTreeViewController

    /// 通用区
    private let generalSettingsViewController = GeneralSettingsViewController(
        preferences: .shared
    )

    /// 创建设置窗口；窗口关闭时只隐藏，不释放
    /// - Parameter dockTileSynchronizer: Dock tile 同步器；Dock 集成不可用时传 nil
    init(dockTileSynchronizer: DockTileSynchronizer?) {
        folderTreeViewController = FolderTreeViewController(
            store: .shared,
            dockTileSynchronizer: dockTileSynchronizer
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: true
        )

        window.title = String(
            localized: "settings.windowTitle",
            comment: "设置窗口的标题"
        )
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 460, height: 480)

        super.init(window: window)

        window.contentView = makeContentView()
        window.delegate = self
        window.center()
    }

    /// 设置窗口完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 显示设置窗口并把它带到最前；这是唯一允许激活 Flotilla 的场景
    func show() {
        guard NSApp.activationPolicy() != .regular else {
            bringToFront()
            return
        }

        // 从 `.accessory` 切到 `.regular` 后系统需要时间准备 Dock 图标，激活与置前延迟到下一个 run loop
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            self?.bringToFront()
        }
    }
}

// MARK: NSWindowDelegate

extension SettingsWindowController: NSWindowDelegate {
    /// 窗口每次来到前台都刷新辅助功能权限状态与 tile 的状态：
    /// 从系统设置授权回来、把 tile 拖出 Dock 后再点开窗口，即可看到结果
    func windowDidBecomeKey(_: Notification) {
        generalSettingsViewController.refreshAccessibilityStatus()
        folderTreeViewController.refreshDockStatus()
    }

    /// 设置窗口关闭后，若没有其它可见窗口就回到 `.accessory`，Dock 图标随之消失
    func windowWillClose(_: Notification) {
        // 只统计能成为主窗口的普通窗口：状态栏按钮所在的窗口与面板都不算
        let hasOtherVisibleWindow = NSApp.windows.contains {
            $0 !== window && $0.isVisible && $0.canBecomeMain
        }

        guard !hasOtherVisibleWindow else { return }

        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Private

extension SettingsWindowController {
    /// 激活 Flotilla 并把设置窗口带到最前
    private func bringToFront() {
        // macOS 14 起 `activate()` 是协作式的：最近一次用户输入不是发给 Flotilla 时
        // （例如用辅助功能按下菜单项）会被系统忽略，窗口开在其它 App 后面
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 文件夹区在上、通用区在下，中间以分隔线隔开；文件夹区随窗口高度伸缩
    private func makeContentView() -> NSView {
        let folderTreeView = folderTreeViewController.view
        let generalSettingsView = generalSettingsViewController.view

        let separator = NSBox()
        separator.boxType = .separator

        let stackView = NSStackView(views: [folderTreeView, separator, generalSettingsView])
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        // 文件夹区与分隔线扣除左右边距后占满宽度
        NSLayoutConstraint.activate([
            folderTreeView.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            separator.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
        ])

        return stackView
    }
}
