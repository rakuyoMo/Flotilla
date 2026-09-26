import CoreGraphics
import Foundation

// MARK: - DockFolderPresenterState

/// 面板展开状态的纯逻辑：把快速路径的鼠标事件、URL 信号与外部点击归并成展开或收起
///
/// 同一次点击 tile 会先后经过快速路径与 URL 两条路径，这里负责让它只生效一次
struct DockFolderPresenterState {
    /// 同一次点击的两路信号相互合并的时间窗（秒）
    static let signalMergeInterval: TimeInterval = 1

    /// 正在展示的根文件夹；nil 表示面板已收起
    private(set) var presentedFolderID: UUID? = nil

    /// 快速路径识别出的、尚未抬起的 tile 按下，记下位置与时间，抬起时据此排除拖动与长按
    private var pendingPress: (folderID: UUID, location: CGPoint, time: TimeInterval)? = nil

    /// 快速路径最近处理的一次 tile 点击，等待与随后到达的 URL 合并
    private var lastTileClick: (folderID: UUID, time: TimeInterval)? = nil

    /// 最近一次因点击 Dock 区域而收起时展示的文件夹，等待与随后到达的 URL 合并
    private var lastDockAreaDismissal: (folderID: UUID, time: TimeInterval)? = nil
}

// MARK: - Signals

extension DockFolderPresenterState {
    /// 鼠标按下（左键、右键、中键）
    /// - Parameters:
    ///   - folderID: 快速路径识别出的 Flotilla tile；nil 表示按在面板以外的其它位置
    ///   - location: 按下的位置
    ///   - isInDockArea: 是否落在 Dock 区域
    ///   - time: 系统启动以来的秒数
    mutating func mouseDown(
        onTile folderID: UUID?,
        at location: CGPoint,
        isInDockArea: Bool,
        time: TimeInterval
    ) -> DockFolderPresenterTransition {
        pendingPress = nil

        // 按在 Flotilla 的 tile 上：等抬起时再判定，按下后拖动（调整 Dock 顺序）或按住不放都不展开
        if let folderID {
            pendingPress = (folderID, location, time)
            return .unchanged
        }

        return dismissForOutsideClick(isInDockArea: isInDockArea, time: time)
    }

    /// 左键拖动：从 tile 上按下后移动超过阈值即视为拖动 tile，不再展开，并按点击其它位置收起
    mutating func mouseDragged(
        to location: CGPoint,
        time: TimeInterval
    ) -> DockFolderPresenterTransition {
        guard let press = pendingPress else { return .unchanged }

        let distance = Self.distance(from: press.location, to: location)

        guard distance > FolderPanelMetrics.dragThreshold else { return .unchanged }

        pendingPress = nil

        return dismissForOutsideClick(isInDockArea: true, time: time)
    }

    /// 左键抬起：完成一次 tile 点击，切换该文件夹的展开状态
    ///
    /// 按住超过 `longPressDuration` 时 Dock 已弹出 App 菜单，这次抬起不算点击，与拖动 tile 一样按点击其它位置收起
    mutating func mouseUp(time: TimeInterval) -> DockFolderPresenterTransition {
        guard let press = pendingPress else { return .unchanged }

        pendingPress = nil

        // 按住太久：不展开；面板正展开时视同点击 Dock 上的其它位置而收起
        guard time - press.time <= FolderPanelMetrics.longPressDuration else {
            return dismissForOutsideClick(isInDockArea: true, time: time)
        }

        lastTileClick = (press.folderID, time)

        return toggle(folderID: press.folderID)
    }

    /// stub 打开的 `flotilla://folder/<id>` 到达
    mutating func receiveURL(
        folderID: UUID,
        time: TimeInterval
    ) -> DockFolderPresenterTransition {
        // 快速路径已处理过这次点击，随后到达的 URL 属于同一次点击
        if
            let click = lastTileClick,
            click.folderID == folderID,
            time - click.time <= Self.signalMergeInterval
        {
            lastTileClick = nil
            return .unchanged
        }

        // 无权限时，再次点击 tile 会先被当作点击 Dock 区域而收起，随后到达的 URL 同样属于这次点击
        if
            let dismissal = lastDockAreaDismissal,
            dismissal.folderID == folderID,
            time - dismissal.time <= Self.signalMergeInterval
        {
            lastDockAreaDismissal = nil
            return .unchanged
        }

        return toggle(folderID: folderID)
    }

    /// 由 Esc、启动 App、屏幕参数变化、文件夹被删除等原因收起
    mutating func dismiss() -> DockFolderPresenterTransition {
        guard presentedFolderID != nil else { return .unchanged }

        presentedFolderID = nil

        return .collapse
    }
}

// MARK: - Private

extension DockFolderPresenterState {
    /// 未展开时展开；已展开同一文件夹时收起；已展开另一个文件夹时直接切换
    private mutating func toggle(folderID: UUID) -> DockFolderPresenterTransition {
        guard presentedFolderID != folderID else {
            presentedFolderID = nil
            return .collapse
        }

        presentedFolderID = folderID

        return .expand(folderID)
    }

    /// 点击面板以外的位置时收起；落在 Dock 区域时记下被收起的文件夹，供随后到达的 URL 合并
    private mutating func dismissForOutsideClick(
        isInDockArea: Bool,
        time: TimeInterval
    ) -> DockFolderPresenterTransition {
        guard let folderID = presentedFolderID else { return .unchanged }

        if isInDockArea {
            lastDockAreaDismissal = (folderID, time)
        }

        presentedFolderID = nil

        return .collapse
    }
}

// MARK: - Helpers

extension DockFolderPresenterState {
    /// 两点之间的直线距离
    private static func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }
}
