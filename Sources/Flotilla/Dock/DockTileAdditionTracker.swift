import Foundation

// MARK: - DockTileAdditionTracker

/// 决定哪些根文件夹要向 Dock 添加 tile 的纯逻辑：只添加新出现的根文件夹与用户要求添加的根文件夹
///
/// 用户可以把 tile 拖出 Dock，拖出后不再自动加回。添加过 tile 的根文件夹先记为待添加，直到确认 tile 已经加上：
/// 被终止的旧 Dock 退出时 tile 仍在 Dock 偏好里，或某次同步看到 tile 在 Dock 上。
/// 旧 Dock 终止时可能把启动时读到的旧条目写回、抹掉刚加的 tile，此时仍待添加，复查时再加一次；
/// 确认之后 tile 不在了，就是被用户拖出去的
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

    /// 重启 Dock 时被终止的旧 Dock 已经退出：此刻 Dock 偏好里已有 tile 的根文件夹不再待添加
    ///
    /// 旧 Dock 终止时的写回已经落地，新拉起的 Dock 读到的就是此刻的偏好，此后它自己的写回保留这些条目
    /// - Parameter onDockFolderIDs: 旧 Dock 退出时 Dock 偏好里有 tile 的根文件夹
    mutating func recordDockTermination(onDockFolderIDs: Set<UUID>) {
        pendingFolderIDs.subtract(onDockFolderIDs)
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
