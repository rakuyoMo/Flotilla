import Foundation

// MARK: - DockTileAdditionTracker

/// 决定哪些根文件夹要向 Dock 添加 tile 的纯逻辑：只添加新出现的根文件夹与用户要求添加的根文件夹
///
/// 用户可以把 tile 拖出 Dock，拖出后不再自动加回。添加过 tile 的根文件夹在同步看到 tile 确实在 Dock 上之前一直待添加：
/// Dock 重启后写回偏好会把刚加的条目盖掉，复查时要再加一次；tile 在 Dock 上出现过、之后又不在了，才是被用户拖出去的
struct DockTileAdditionTracker {
    /// 上一次同步时的根文件夹，据此判断哪些根文件夹是新出现的
    private var syncedRootFolderIDs: Set<UUID>

    /// 待添加 tile 的根文件夹
    private var pendingFolderIDs: Set<UUID> = []

    /// 创建追踪器；启动时的根文件夹都视为已同步过
    ///
    /// Flotilla 没运行时不会有新的根文件夹出现，此时缺少 tile 的根文件夹都是被用户拖出去的
    /// - Parameter rootFolderIDs: 启动时的根文件夹
    init(rootFolderIDs: Set<UUID>) {
        syncedRootFolderIDs = rootFolderIDs
    }

    /// 用户要求把该根文件夹添加到 Dock
    mutating func request(folderID: UUID) {
        pendingFolderIDs.insert(folderID)
    }

    /// 本次同步要添加 tile 的根文件夹：待添加的与新出现的，去掉已在 Dock 上的与已不是根文件夹的；
    /// 返回的集合就是同步之后仍待添加的集合
    /// - Parameters:
    ///   - rootFolderIDs: 本次同步时的根文件夹
    ///   - onDockFolderIDs: Dock 上现有 tile 对应的根文件夹
    mutating func folderIDsToAdd(
        rootFolderIDs: Set<UUID>,
        onDockFolderIDs: Set<UUID>
    ) -> Set<UUID> {
        // 上一次同步时还不是根文件夹的：新建的根文件夹，或被拖成根文件夹的子文件夹
        let newFolderIDs = rootFolderIDs.subtracting(syncedRootFolderIDs)
        syncedRootFolderIDs = rootFolderIDs

        // 看到 tile 已在 Dock 上的不再待添加；被删除或被拖成子文件夹的也不再添加
        pendingFolderIDs = pendingFolderIDs
            .union(newFolderIDs)
            .intersection(rootFolderIDs)
            .subtracting(onDockFolderIDs)

        return pendingFolderIDs
    }

    /// 被用户拖出 Dock 的根文件夹：tile 不在 Dock 上，下一次同步也不会添加
    ///
    /// 新出现的（上一次同步时还不是根文件夹）与待添加的根文件夹都不算：它们的 tile 只是还没加上
    /// - Parameters:
    ///   - rootFolderIDs: 当前的根文件夹
    ///   - onDockFolderIDs: Dock 上现有 tile 对应的根文件夹
    func removedFolderIDs(
        rootFolderIDs: Set<UUID>,
        onDockFolderIDs: Set<UUID>
    ) -> Set<UUID> {
        rootFolderIDs
            .intersection(syncedRootFolderIDs)
            .subtracting(pendingFolderIDs)
            .subtracting(onDockFolderIDs)
    }
}
