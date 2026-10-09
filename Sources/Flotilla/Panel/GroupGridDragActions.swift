import CoreGraphics

// MARK: - GroupGridDragActions

/// 组的层级交给网格的拖动判定与动作：鼠标是否在当前层级的轮廓之内、是否在 “移除” 的边界之内，
/// 松开时更新点击穿透，松开后保存新的顺序或删除这一项
///
/// 访达文件夹的层级没有，其中各项不能拖动
struct GroupGridDragActions {
    /// 屏幕上的点（AppKit 屏幕坐标）是否在当前层级的轮廓之内：面板主体与尾巴
    let containsScreenPoint: @MainActor (CGPoint) -> Bool

    /// 屏幕上的点（AppKit 屏幕坐标）是否在当前层级 “移除” 的边界之内：面板主体向外扩出的圆角矩形
    let removeBoundaryContainsScreenPoint: @MainActor (CGPoint) -> Bool

    /// 松开时执行，落进目标格、删除与落回原位都是：面板按鼠标当时的位置更新点击穿透
    ///
    /// 点击穿透平时只在鼠标移动时更新，拖动期间不变；落回原位不重建面板，要在松开时更新，
    /// 鼠标停在轮廓之外直接点击，点击才穿透到下面的窗口
    let releaseHandler: @MainActor () -> Void

    /// 在轮廓之内另一格松开、落定之后执行，拿到拖动的项与目标格（移动之后的下标）
    let moveHandler: @MainActor (GroupItem, Int) -> Void

    /// “移除” 浮出之后松开时执行，拿到拖动的项
    let removeHandler: @MainActor (GroupItem) -> Void
}
