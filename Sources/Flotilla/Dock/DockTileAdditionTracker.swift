import Foundation

// MARK: - DockTileAdditionTracker

/// 决定哪些根文件夹要向 Dock 添加 tile 的纯逻辑：只添加新出现的根文件夹与用户要求添加的根文件夹
///
/// 用户可以把 tile 拖出 Dock，拖出后不再自动加回。添加过 tile 的根文件夹先记为待添加，直到确认 tile 已经加上：
/// 重启后的 Dock 读到了含有这个 tile 的偏好，或某次同步看到 tile 在 Dock 上；确认之后 tile 不在了，就是被用户拖出去的。
///
/// 新建的根文件夹在名称定下来之前先搁置：既不添加 tile，也不算被拖出，名称定下来后 tile 带着最终名称一次出现
struct DockTileAdditionTracker {
    /// 上一次同步时的根文件夹，据此判断哪些根文件夹是新出现的；搁置中的根文件夹不计入
    private var syncedRootFolderIDs: Set<UUID>

    /// 待添加 tile 的根文件夹
    private var pendingFolderIDs: Set<UUID> = []

    /// 搁置中的根文件夹：新建后正在输入名称
    private var heldFolderIDs: Set<UUID> = []

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

    /// 搁置新建的根文件夹：名称定下来之前不添加 tile
    mutating func hold(folderID: UUID) {
        heldFolderIDs.insert(folderID)
    }

    /// 解除搁置：此后的同步把它当作新出现的根文件夹添加 tile
    /// - Returns: 该根文件夹此前是否在搁置中
    @discardableResult
    mutating func release(folderID: UUID) -> Bool {
        heldFolderIDs.remove(folderID) != nil
    }

    /// 重启后的 Dock 已读到期望的偏好：此刻偏好里已有 tile 的根文件夹确认加上，不再待添加
    ///
    /// 此后新 Dock 自己的写回也保留这些条目
    /// - Parameter onDockFolderIDs: 新 Dock 读到的偏好里有 tile 的根文件夹
    mutating func recordDockRelaunch(onDockFolderIDs: Set<UUID>) {
        pendingFolderIDs.subtract(onDockFolderIDs)
    }

    /// 本次同步要添加 tile 的根文件夹：待添加的与新出现的，去掉已在 Dock 上的、已不是根文件夹的与搁置中的；
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

        // 搁置中的不记为已同步：解除搁置后的那次同步仍把它当作新出现的
        syncedRootFolderIDs = rootFolderIDs.subtracting(heldFolderIDs)

        // 看到 tile 已在 Dock 上的不再待添加；被删除或被拖成子文件夹的也不再添加
        pendingFolderIDs = pendingFolderIDs
            .union(newFolderIDs)
            .intersection(rootFolderIDs)
            .subtracting(onDockFolderIDs)
            .subtracting(heldFolderIDs)

        return pendingFolderIDs
    }

    /// 被用户拖出 Dock 的根文件夹：tile 不在 Dock 上，下一次同步也不会添加
    ///
    /// 新出现的（上一次同步时还不是根文件夹）、搁置中的与待添加的根文件夹都不算：它们的 tile 只是还没加上
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
            .subtracting(heldFolderIDs)
            .subtracting(onDockFolderIDs)
    }
}
