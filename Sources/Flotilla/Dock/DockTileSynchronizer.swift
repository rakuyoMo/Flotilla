import AppKit
import os

// MARK: - DockTileSynchronizer

/// 让 Dock 上的 tile 与根文件夹保持一致：每个根文件夹对应一个 stub 与一个 tile，名称与图标随文件夹实时更新
@MainActor
final class DockTileSynchronizer: NSObject {
    /// 合并连续变更的防抖间隔
    private static let debounceInterval = Duration.milliseconds(500)

    /// stub 图标的渲染边长（点），与 iconset 的最大一档一致
    private static let iconPointSize: CGFloat = 512

    /// 同步相关的日志
    private static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "DockTileSynchronizer"
    )

    /// 文件夹树的唯一数据源
    private let store: FolderStore

    /// 用户设置，决定图标里的预览数量
    private let preferences: Preferences

    /// 生成、更新、删除 stub
    private let builder: DockTileBundleBuilder

    /// 读写 Dock 偏好
    private let dockPreferences: DockPreferences

    /// 防抖期间等待执行的同步；新的变更到来时取消并替换它
    private var pendingSynchronization: Task<Void, Never>?

    /// 对 App 外观的观察：stub 图标按 App 当时的外观渲染，系统切换深浅后要重新同步
    private var appearanceObservation: NSKeyValueObservation?

    /// 创建同步器
    /// - Parameters:
    ///   - store: 文件夹树的唯一数据源
    ///   - preferences: 用户设置，决定图标里的预览数量
    ///   - builder: 生成、更新、删除 stub
    ///   - dockPreferences: 读写 Dock 偏好
    init(
        store: FolderStore,
        preferences: Preferences,
        builder: DockTileBundleBuilder,
        dockPreferences: DockPreferences
    ) {
        self.store = store
        self.preferences = preferences
        self.builder = builder
        self.dockPreferences = dockPreferences
    }

    /// 先对账一次，再订阅文件夹树、设置与系统外观的变更
    func start() {
        synchronize()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleSynchronization),
            name: FolderStore.didChangeNotification,
            object: store
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleSynchronization),
            name: Preferences.didChangeNotification,
            object: preferences
        )

        // 观察渲染 stub 图标时读取的同一个值：App 没有固定外观，这个值跟随系统的深浅；
        // 它在主线程上变化，观察回调也在主线程。
        // 深浅切换后底板颜色变了，同步时 stub 被改写、tile 换新的 GUID，Dock 因此重启一次：
        // Dock 按 GUID 缓存 tile 图标，不重启不会换图（见 02 文档）
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.scheduleSynchronization()
            }
        }
    }
}

// MARK: - Private

extension DockTileSynchronizer {
    /// 防抖：连续变更只在最后一次之后同步一次，避免拖拽、连续添加时反复重启 Dock
    @objc
    private func scheduleSynchronization() {
        pendingSynchronization?.cancel()
        pendingSynchronization = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }

            self?.synchronize()
        }
    }

    /// 按当前的根文件夹对账：更新 stub、增删改 tile，Dock 需要刷新时重启它，最后清理多余的 stub
    private func synchronize() {
        let rootFolders = store.rootFolders
        let previewIconCount = preferences.previewIconCount

        // 逐个同步全部根文件夹，每个都要执行，不能在第一个需要重启时短路
        let restartRequests = rootFolders.map {
            synchronizeTile(of: $0, previewIconCount: previewIconCount)
        }

        // 已删除或被拖成子文件夹的根文件夹：先删 tile，Dock 不再引用后才删 stub
        let staleIDs = builder.existingFolderIDs().subtracting(rootFolders.map(\.id))
        let staleTiles = removeTiles(of: staleIDs)

        if restartRequests.contains(true) || staleTiles.needsDockRestart {
            dockPreferences.restartDock()
        }

        removeStubs(of: staleTiles.removableIDs)
    }

    /// 让一个根文件夹的 stub 与 tile 与数据一致
    /// - Returns: 是否需要重启 Dock
    private func synchronizeTile(of folder: Folder, previewIconCount: Int) -> Bool {
        let tileURL = builder.bundleURL(for: folder)

        // stub 图标没有所在的视图，按 App 当前的外观取底板颜色
        let icon = FolderIconRenderer.render(
            folder: folder,
            previewIconCount: previewIconCount,
            pointSize: Self.iconPointSize,
            appearance: FolderIconAppearance(NSApp.effectiveAppearance)
        )

        do {
            // stub 写入失败时不动 tile，避免 Dock 上出现指向残缺 stub 的图标
            let isBundleChanged = try builder.write(folder: folder, icon: icon)

            guard dockPreferences.contains(tileURL: tileURL) else {
                try dockPreferences.add(tileURL: tileURL, label: folder.name)
                return true
            }

            // Dock 按条目的 GUID 缓存 tile 图标，stub 改写后只重启 Dock 仍显示旧图标；
            // update 在 stub 改写过时给条目换一个新的 GUID 并返回 true，由调用方重启 Dock
            return try dockPreferences.update(
                tileURL: tileURL,
                label: folder.name,
                isStubRewritten: isBundleChanged
            )
        } catch {
            Self.logger.error(
                "同步 tile 失败（\(folder.id.uuidString, privacy: .public)）：\(error.localizedDescription, privacy: .public)"
            )

            return false
        }
    }

    /// 从 Dock 偏好中删除这些根文件夹的 tile
    /// - Returns: tile 已不在 Dock 上、可以删除 stub 的根文件夹，以及是否需要重启 Dock
    private func removeTiles(
        of folderIDs: Set<UUID>
    ) -> (removableIDs: [UUID], needsDockRestart: Bool) {
        var removableIDs: [UUID] = []
        var needsDockRestart = false

        for folderID in folderIDs {
            do {
                // tile 按 stub 独占的目录匹配：用户在访达里删掉了 stub bundle 时，Dock 上失效的条目同样删除
                let tileDirectory = builder.folderDirectory(for: folderID)

                if try dockPreferences.remove(tileDirectory: tileDirectory) {
                    needsDockRestart = true
                }

                removableIDs.append(folderID)
            } catch {
                // tile 删除失败时保留 stub，让 Dock 上残留的 tile 仍然可用，下次对账再删
                Self.logger.error(
                    "删除 tile 失败（\(folderID.uuidString, privacy: .public)）：\(error.localizedDescription, privacy: .public)"
                )
            }
        }

        return (removableIDs, needsDockRestart)
    }

    /// 删除这些根文件夹的 stub
    private func removeStubs(of folderIDs: [UUID]) {
        for folderID in folderIDs {
            do {
                try builder.remove(folderID: folderID)
            } catch {
                Self.logger.error(
                    "删除 stub 失败（\(folderID.uuidString, privacy: .public)）：\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
