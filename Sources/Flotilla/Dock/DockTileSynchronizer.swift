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

    /// Dock 偏好里的 tile 有变化时发出，`object` 为同步器；包括 Dock 自己写入的改动，例如用户把 tile 拖出 Dock
    nonisolated static let dockTilesDidChangeNotification = Notification.Name(
        "DockTileSynchronizer.dockTilesDidChange"
    )

    /// stub 图标的渲染边长（pt），与 iconset 的最大一档一致
    private static let iconPointSize: CGFloat = 512

    /// 合并连续变更的防抖间隔：
    /// 拖动、连续添加时只在最后一次变更之后同步一次，避免反复重启 Dock
    private static let debounceInterval = Duration.milliseconds(500)

    /// 一次同步最多重启 Dock 的次数：补写赶不上新 Dock 读取偏好时再重启一次，超过就放弃
    private static let maximumDockRestartCount = 3

    /// 同步相关的日志
    private static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "DockTileSynchronizer"
    )

    /// 文件夹树的唯一数据源
    private let store: GroupStore

    /// 用户设置，决定图标里的预览数量
    private let preferences: Preferences

    /// 生成、更新、删除 stub
    private let builder: DockTileBundleBuilder

    /// 读写 Dock 偏好
    private let dockPreferences: DockPreferences

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
        store: GroupStore,
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
            rootGroupIDs: Set(store.rootGroups.map(\.id))
        )
    }

    /// 先同步一次，再订阅文件夹树、设置、系统外观与 Dock 偏好的变更
    func start() {
        synchronize()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scheduleSynchronization),
            name: GroupStore.didChangeNotification,
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
        // Dock 按 GUID 缓存 tile 图标，不重启不会换图
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.scheduleSynchronization()
            }
        }

        // 用户把 tile 拖出 Dock 后，Dock 约 4 秒才把删除写进偏好：写入时通知设置窗口刷新状态，不触发同步
        dockPreferences.observeTiles { [weak self] in
            guard let self else { return }

            NotificationCenter.default.post(
                name: Self.dockTilesDidChangeNotification,
                object: self
            )
        }
    }

    /// 被用户拖出 Dock 的根文件夹：tile 不在 Dock 上，下一次同步也不会添加；设置窗口据此显示状态
    ///
    /// 刚新建、还没同步的根文件夹，搁置中的根文件夹，以及已经要求添加的根文件夹都不算
    func rootGroupIDsRemovedFromDock() -> Set<UUID> {
        additionTracker.removedGroupIDs(
            rootGroupIDs: Set(store.rootGroups.map(\.id)),
            onDockGroupIDs: rootGroupIDsOnDock()
        )
    }

    /// 把根文件夹记为待添加，并安排一次同步；用于把被拖出 Dock 的 tile 重新添加回去
    func addTile(for groupID: UUID) {
        additionTracker.request(groupID: groupID)
        scheduleSynchronization()
    }

    /// 新建的根文件夹开始输入名称：
    /// 名称定下来之前不添加 tile，免得 tile 先以默认名出现、重命名后 Dock 再重启一次
    func holdTile(for groupID: UUID) {
        additionTracker.hold(groupID: groupID)
    }

    /// 名称编辑结束：解除搁置并安排一次同步，tile 带着最终名称出现；不在搁置中的文件夹忽略
    func releaseTile(for groupID: UUID) {
        guard additionTracker.release(groupID: groupID) else { return }

        scheduleSynchronization()
    }
}

// MARK: - Synchronization

extension DockTileSynchronizer {
    /// 变更到达：防抖间隔之后同步，之前等待中的同步随之取消
    @objc
    private func scheduleSynchronization() {
        pendingSynchronization?.cancel()
        pendingSynchronization = Task { [weak self] in
            try? await Task.sleep(for: Self.debounceInterval)
            guard !Task.isCancelled else { return }

            self?.synchronize()
        }
    }

    /// 按当前的根文件夹同步：更新 stub，把 tile 的期望状态写进 Dock 偏好；
    /// 偏好有改动时重启 Dock，等新 Dock 读到期望状态后才算同步结束；
    /// 结束时清理多余的 stub 并发出 `didSynchronizeNotification`
    private func synchronize() {
        let rootGroups = store.rootGroups

        // 缺少 tile 的根文件夹里，只有新出现的与用户要求添加的才添加；其余是被用户拖出 Dock 的
        let groupIDsToAdd = additionTracker.groupIDsToAdd(
            rootGroupIDs: Set(rootGroups.map(\.id)),
            onDockGroupIDs: rootGroupIDsOnDock()
        )

        let stubs = writeStubs(of: rootGroups, groupIDsToAdd: groupIDsToAdd)

        // 已删除或被拖成子文件夹的根文件夹：先删 tile，新 Dock 不再引用后才删 stub。
        // 候选既取磁盘上现存的 stub 目录，也取 Dock 上指向 stub 目录的 tile：
        // 整个 `<id>` 目录已不存在时，Dock 上残留的 tile 同样要删
        let staleIDs = builder.existingGroupIDs()
            .union(rootGroupIDsOnDock())
            .subtracting(rootGroups.map(\.id))

        do {
            let isChanged = try dockPreferences.apply(
                stubs.expectedTiles,
                rewrittenTileURLs: stubs.rewrittenTileURLs,
                removingTilesIn: staleIDs.map { builder.groupDirectory(for: $0) }
            )

            guard isChanged else {
                finishSynchronization(removingStubsOf: staleIDs)
                return
            }

            restartDock(
                verifying: stubs.expectedTiles,
                staleIDs: staleIDs,
                restartCount: 1
            )
        } catch {
            // 偏好没有写入，多余的 tile 可能还在 Dock 上：
            // 保留它们的 stub，下次同步再删
            Self.logger.error("写入 Dock 偏好失败：\(error.localizedDescription, privacy: .public)")

            NotificationCenter.default.post(name: Self.didSynchronizeNotification, object: self)
        }
    }

    /// 重启 Dock，旧 Dock 退出后核对新 Dock 读到的偏好
    /// - Parameters:
    ///   - expectedTiles: 本次同步写入的 tile 期望状态
    ///   - staleIDs: 本次同步删除 tile 的根文件夹
    ///   - restartCount: 这是本次同步第几次重启 Dock
    private func restartDock(
        verifying expectedTiles: [ExpectedDockTile],
        staleIDs: Set<UUID>,
        restartCount: Int
    ) {
        dockPreferences.restartDock { [weak self] in
            self?.verifyRelaunchedDock(
                expectedTiles: expectedTiles,
                staleIDs: staleIDs,
                restartCount: restartCount
            )
        }
    }

    /// 旧 Dock 已退出：它终止时可能把启动时读到的旧条目写回，盖掉刚写入的期望状态；
    /// 按同一份期望再写一次，补写赶在新 Dock 读取偏好之前才算新 Dock 读到了，否则再重启一次
    /// - Parameters:
    ///   - expectedTiles: 本次同步写入的 tile 期望状态
    ///   - staleIDs: 本次同步删除 tile 的根文件夹
    ///   - restartCount: 这是本次同步第几次重启 Dock
    private func verifyRelaunchedDock(
        expectedTiles: [ExpectedDockTile],
        staleIDs: Set<UUID>,
        restartCount: Int
    ) {
        let isRewritten: Bool

        do {
            isRewritten = try dockPreferences.apply(
                expectedTiles,
                rewrittenTileURLs: [],
                removingTilesIn: staleIDs.map { builder.groupDirectory(for: $0) }
            )
        } catch {
            Self.logger.error("补写 Dock 偏好失败：\(error.localizedDescription, privacy: .public)")

            finishSynchronization(removingStubsOf: staleIDs)
            return
        }

        // 没有补写时，新 Dock 读到的要么是第一次写入的内容，要么是与期望一致的写回
        guard isRewritten, !isRewriteRead() else {
            // 新 Dock 读到了期望状态：此后 tile 不在 Dock 上，就是用户拖出去的
            additionTracker.recordDockRelaunch(onDockGroupIDs: rootGroupIDsOnDock())

            finishSynchronization(removingStubsOf: staleIDs)
            return
        }

        guard restartCount < Self.maximumDockRestartCount else {
            // 偏好里已是期望状态，Dock 下一次重启时会读到
            Self.logger.error("重启 Dock \(restartCount) 次，补写仍晚于新 Dock 读取偏好，放弃核对")

            finishSynchronization(removingStubsOf: staleIDs)
            return
        }

        Self.logger.notice("旧 Dock 终止时写回了旧条目，补写晚于新 Dock 读取偏好，再重启一次 Dock")

        restartDock(
            verifying: expectedTiles,
            staleIDs: staleIDs,
            restartCount: restartCount + 1
        )
    }

    /// 刚完成的补写是否一定会被新拉起的 Dock 读到
    private func isRewriteRead() -> Bool {
        // 先记下补写完成的时刻再找新 Dock：在这之后才启动的 Dock 一定读到补写
        let writtenAt = Date()

        return DockPreferences.isReadByRelaunchedDock(
            writtenAt: writtenAt,
            dockLaunchedAt: dockPreferences.relaunchedDockLaunchDate()
        )
    }

    /// 同步结束：删掉 tile 已从偏好里删除的 stub，通知设置窗口刷新状态
    /// - Parameter staleIDs: 本次同步删除 tile 的根文件夹
    private func finishSynchronization(removingStubsOf staleIDs: Set<UUID>) {
        removeStubs(of: staleIDs)

        NotificationCenter.default.post(name: Self.didSynchronizeNotification, object: self)
    }

    /// Dock 上现有 tile 对应的根文件夹 id
    private func rootGroupIDsOnDock() -> Set<UUID> {
        dockPreferences.groupIDs(ofTilesIn: builder.directory)
    }
}

// MARK: - Stubs

extension DockTileSynchronizer {
    /// 逐个更新全部根文件夹的 stub，给出它们的 tile 应有的样子；stub 写入失败的根文件夹不动它的 tile，
    /// 避免 Dock 上出现指向残缺 stub 的图标
    /// - Parameters:
    ///   - rootGroups: 本次同步时的根文件夹
    ///   - groupIDsToAdd: tile 不在 Dock 上时要添加的根文件夹
    /// - Returns: 各 tile 的期望状态，以及 stub 被改写过、条目要换新 GUID 的 tile
    private func writeStubs(
        of rootGroups: [Group],
        groupIDsToAdd: Set<UUID>
    ) -> (expectedTiles: [ExpectedDockTile], rewrittenTileURLs: Set<URL>) {
        let previewIconCount = preferences.previewIconCount

        var expectedTiles: [ExpectedDockTile] = []
        var rewrittenTileURLs: Set<URL> = []

        for group in rootGroups {
            guard
                let isRewritten = writeStub(of: group, previewIconCount: previewIconCount)
            else {
                continue
            }

            let tileURL = builder.bundleURL(for: group)

            expectedTiles.append(
                ExpectedDockTile(
                    tileURL: tileURL,
                    label: group.name,
                    canAdd: groupIDsToAdd.contains(group.id)
                )
            )

            // Dock 按条目的 GUID 缓存 tile 图标，stub 改写后只重启 Dock 仍显示旧图标，条目要换新的 GUID
            if isRewritten {
                rewrittenTileURLs.insert(tileURL)
            }
        }

        return (expectedTiles, rewrittenTileURLs)
    }

    /// 按当前外观渲染根文件夹的图标，内容有变化时改写它的 stub
    /// - Parameters:
    ///   - group: 根文件夹
    ///   - previewIconCount: 图标里叠加的预览图标数量
    /// - Returns: stub 是否被改写；写入失败时为 nil
    private func writeStub(of group: Group, previewIconCount: Int) -> Bool? {
        // stub 图标没有所在的视图，按 App 当前的外观取底板颜色
        let icon = GroupIconRenderer.render(
            group: group,
            previewIconCount: previewIconCount,
            pointSize: Self.iconPointSize,
            appearance: GroupIconAppearance(NSApp.effectiveAppearance)
        )

        do {
            return try builder.write(group: group, icon: icon)
        } catch {
            Self.logger.error(
                "写入 stub 失败（\(group.id.uuidString, privacy: .public)）：\(error.localizedDescription, privacy: .public)"
            )

            return nil
        }
    }

    /// 删除这些根文件夹的 stub
    private func removeStubs(of groupIDs: Set<UUID>) {
        for groupID in groupIDs {
            do {
                try builder.remove(groupID: groupID)
            } catch {
                Self.logger.error(
                    "删除 stub 失败（\(groupID.uuidString, privacy: .public)）：\(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }
}
