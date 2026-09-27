import AppKit
import os

// MARK: - DockTileSynchronizer

/// 让 Dock 上的 tile 与根文件夹保持一致：每个根文件夹对应一个 stub 与一个 tile，名称与图标随文件夹实时更新
///
/// 用户把 tile 拖出 Dock 后不自动加回，只在根文件夹新出现或用户要求添加时添加 tile
@MainActor
final class DockTileSynchronizer: NSObject {
    /// 每次同步结束后发出，`object` 为同步器；设置窗口据此刷新 tile 是否在 Dock 上
    nonisolated static let didSynchronizeNotification = Notification.Name(
        "DockTileSynchronizer.didSynchronize"
    )

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

    /// 同步时机：防抖、Dock 重启后的静默期与复查
    private var schedule = DockSynchronizationSchedule()

    /// 决定哪些根文件夹要添加 tile
    private var additionTracker: DockTileAdditionTracker

    /// 等待执行的同步；新的变更到来时取消并替换它
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

        // 创建时就有的根文件夹都视为已同步过：其中缺少 tile 的，是用户在 Flotilla 没运行时拖出去的
        additionTracker = DockTileAdditionTracker(
            rootFolderIDs: Set(store.rootFolders.map(\.id))
        )
    }

    /// 先对账一次，再订阅文件夹树、设置与系统外观的变更
    func start() {
        synchronize(isRecheck: false)

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

    /// 被用户拖出 Dock 的根文件夹：tile 不在 Dock 上，下一次同步也不会添加；设置窗口据此显示状态
    ///
    /// 刚新建、还没同步的根文件夹，以及已经要求添加的根文件夹都不算
    func rootFolderIDsRemovedFromDock() -> Set<UUID> {
        additionTracker.removedFolderIDs(
            rootFolderIDs: Set(store.rootFolders.map(\.id)),
            onDockFolderIDs: rootFolderIDsOnDock()
        )
    }

    /// 把根文件夹记为待添加，并安排一次同步；用于把被拖出 Dock 的 tile 重新添加回去
    func addTile(for folderID: UUID) {
        additionTracker.request(folderID: folderID)
        scheduleSynchronization()
    }
}

// MARK: - Private

extension DockTileSynchronizer {
    /// 变更到达：连续变更只在最后一次之后同步一次，避免拖拽、连续添加时反复重启 Dock；
    /// Dock 重启后静默期内到来的变更推迟到静默期结束，免得写入的改动被 Dock 的写回覆盖
    @objc
    private func scheduleSynchronization() {
        let time = schedule.synchronizationTime(forChangeAt: .now)

        // 等待中的复查由这次同步代替：它不早于静默期结束，同样会重新读取 Dock 偏好对账
        synchronize(at: time, isRecheck: false)
    }

    /// Dock 上现有 tile 对应的根文件夹 id
    private func rootFolderIDsOnDock() -> Set<UUID> {
        dockPreferences.folderIDs(ofTilesIn: builder.directory)
    }

    /// 在指定时刻同步；之前等待中的同步随之取消
    /// - Parameters:
    ///   - time: 执行同步的时刻
    ///   - isRecheck: 是否为重启 Dock 之后的复查
    private func synchronize(at time: ContinuousClock.Instant, isRecheck: Bool) {
        pendingSynchronization?.cancel()
        pendingSynchronization = Task { [weak self] in
            try? await Task.sleep(until: time, clock: .continuous)
            guard !Task.isCancelled else { return }

            self?.synchronize(isRecheck: isRecheck)
        }
    }

    /// 按当前的根文件夹对账：更新 stub、增删改 tile，Dock 需要刷新时重启它，最后清理多余的 stub；
    /// 重启了 Dock 时，安排静默期结束时的复查；结束后发出 `didSynchronizeNotification`
    /// - Parameter isRecheck: 是否为重启 Dock 之后的复查
    private func synchronize(isRecheck: Bool) {
        let rootFolders = store.rootFolders
        let previewIconCount = preferences.previewIconCount

        // 缺少 tile 的根文件夹里，只有新出现的与用户要求添加的才添加；其余是被用户拖出 Dock 的
        let folderIDsToAdd = additionTracker.folderIDsToAdd(
            rootFolderIDs: Set(rootFolders.map(\.id)),
            onDockFolderIDs: rootFolderIDsOnDock()
        )

        // 逐个同步全部根文件夹，每个都要执行，不能在第一个需要重启时短路
        let restartRequests = rootFolders.map {
            synchronizeTile(
                of: $0,
                previewIconCount: previewIconCount,
                canAddTile: folderIDsToAdd.contains($0.id)
            )
        }

        // 已删除或被拖成子文件夹的根文件夹：先删 tile，Dock 不再引用后才删 stub。
        // 候选既取磁盘上现存的 stub 目录，也取 Dock 上指向 stub 目录的 tile：
        // 整个 `<id>` 目录已不存在时，Dock 上残留的 tile 同样要删
        let candidateIDs = builder.existingFolderIDs()
            .union(dockPreferences.folderIDs(ofTilesIn: builder.directory))
        let staleIDs = candidateIDs.subtracting(rootFolders.map(\.id))
        let staleTiles = removeTiles(of: staleIDs)

        let needsDockRestart = restartRequests.contains(true) || staleTiles.needsDockRestart

        // 旧 Dock 退出时读一次偏好：刚加的 tile 还在，就是新拉起的 Dock 读到了它，不再待添加；
        // 被旧 Dock 终止时的写回抹掉的仍待添加，由复查再加一次
        if needsDockRestart {
            dockPreferences.restartDock { [weak self] in
                guard let self else { return }

                additionTracker.recordDockTermination(onDockFolderIDs: rootFolderIDsOnDock())
            }
        }

        removeStubs(of: staleTiles.removableIDs)

        // 重启后的 Dock 会把启动时读到的偏好写回一次，可能覆盖刚写入的改动：静默期结束时再对账一次
        let recheckTime = schedule.recordSynchronization(
            at: .now,
            didRestartDock: needsDockRestart,
            isRecheck: isRecheck
        )

        if let recheckTime {
            synchronize(at: recheckTime, isRecheck: true)
        }

        NotificationCenter.default.post(name: Self.didSynchronizeNotification, object: self)
    }

    /// 让一个根文件夹的 stub 与 tile 与数据一致
    /// - Parameters:
    ///   - folder: 根文件夹
    ///   - previewIconCount: 图标里叠加的 App 图标数量
    ///   - canAddTile: tile 不在 Dock 上时是否添加；不添加时只更新 stub
    /// - Returns: 是否需要重启 Dock
    private func synchronizeTile(
        of folder: Folder,
        previewIconCount: Int,
        canAddTile: Bool
    ) -> Bool {
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
                // 被用户拖出 Dock 的 tile 不加回；stub 照常保留，重新添加时直接引用
                guard canAddTile else { return false }

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
