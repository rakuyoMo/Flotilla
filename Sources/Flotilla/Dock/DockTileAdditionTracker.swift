import Foundation

// MARK: - DockTileAdditionTracker

/// 决定哪些根组要向 Dock 添加 tile 的纯逻辑：只添加新出现的根组与用户要求添加的根组
///
/// 用户可以把 tile 拖出 Dock，拖出后不再自动加回。添加过 tile 的根组先记为待添加，直到确认 tile 已经加上：
/// 重启后的 Dock 读到了含有这个 tile 的偏好，或某次同步看到 tile 在 Dock 上；确认之后 tile 不在了，就是被用户拖出去的。
///
/// 新建的根组在名称定下来之前先搁置：既不添加 tile，也不算被拖出，名称定下来后 tile 带着最终名称一次出现
struct DockTileAdditionTracker {
    /// 上一次同步时的根组，据此判断哪些根组是新出现的；搁置中的根组不计入
    private var syncedRootGroupIDs: Set<UUID>

    /// 待添加 tile 的根组
    private var pendingGroupIDs: Set<UUID> = []

    /// 搁置中的根组：新建后正在输入名称
    private var heldGroupIDs: Set<UUID> = []

    /// 创建追踪器；启动时的根组都视为已同步过
    ///
    /// Flotilla 没运行时不会有新的根组出现，此时缺少 tile 的根组都是被用户拖出去的
    /// - Parameter rootGroupIDs: 启动时的根组
    init(rootGroupIDs: Set<UUID>) {
        syncedRootGroupIDs = rootGroupIDs
    }

    /// 用户要求把该根组添加到 Dock
    mutating func request(groupID: UUID) {
        pendingGroupIDs.insert(groupID)
    }

    /// 搁置新建的根组：名称定下来之前不添加 tile
    mutating func hold(groupID: UUID) {
        heldGroupIDs.insert(groupID)
    }

    /// 解除搁置：此后的同步把它当作新出现的根组添加 tile
    /// - Returns: 该根组此前是否在搁置中
    @discardableResult
    mutating func release(groupID: UUID) -> Bool {
        heldGroupIDs.remove(groupID) != nil
    }

    /// 重启后的 Dock 已读到期望的偏好：此刻偏好里已有 tile 的根组确认加上，不再待添加
    ///
    /// 此后新 Dock 自己的写回也保留这些条目
    /// - Parameter onDockGroupIDs: 新 Dock 读到的偏好里有 tile 的根组
    mutating func recordDockRelaunch(onDockGroupIDs: Set<UUID>) {
        pendingGroupIDs.subtract(onDockGroupIDs)
    }

    /// 本次同步要添加 tile 的根组：待添加的与新出现的，去掉已在 Dock 上的、已不是根组的与搁置中的；
    /// 返回的集合就是同步之后仍待添加的集合
    /// - Parameters:
    ///   - rootGroupIDs: 本次同步时的根组
    ///   - onDockGroupIDs: Dock 上现有 tile 对应的根组
    mutating func groupIDsToAdd(
        rootGroupIDs: Set<UUID>,
        onDockGroupIDs: Set<UUID>
    ) -> Set<UUID> {
        // 上一次同步时还不是根组的：新建的根组，或被拖成根组的子组
        let newGroupIDs = rootGroupIDs.subtracting(syncedRootGroupIDs)

        // 搁置中的不记为已同步：解除搁置后的那次同步仍把它当作新出现的
        syncedRootGroupIDs = rootGroupIDs.subtracting(heldGroupIDs)

        // 看到 tile 已在 Dock 上的不再待添加；被删除或被拖成子组的也不再添加
        pendingGroupIDs = pendingGroupIDs
            .union(newGroupIDs)
            .intersection(rootGroupIDs)
            .subtracting(onDockGroupIDs)
            .subtracting(heldGroupIDs)

        return pendingGroupIDs
    }

    /// 被用户拖出 Dock 的根组：tile 不在 Dock 上，下一次同步也不会添加
    ///
    /// 新出现的（上一次同步时还不是根组）、搁置中的与待添加的根组都不算：它们的 tile 只是还没加上
    /// - Parameters:
    ///   - rootGroupIDs: 当前的根组
    ///   - onDockGroupIDs: Dock 上现有 tile 对应的根组
    func removedGroupIDs(
        rootGroupIDs: Set<UUID>,
        onDockGroupIDs: Set<UUID>
    ) -> Set<UUID> {
        rootGroupIDs
            .intersection(syncedRootGroupIDs)
            .subtracting(pendingGroupIDs)
            .subtracting(heldGroupIDs)
            .subtracting(onDockGroupIDs)
    }
}
