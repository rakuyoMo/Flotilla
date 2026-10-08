import CoreGraphics

// MARK: - FolderGridDragActions

/// 文件夹的层级交给网格的拖动判定与动作：鼠标是否在当前层级的轮廓之内，松开后保存新的顺序
///
/// 访达里的文件夹的层级没有，其中各项不能拖动
struct FolderGridDragActions {
    /// 屏幕上的点（AppKit 屏幕坐标）是否在当前层级的轮廓之内：面板主体与尾巴
    let containsScreenPoint: @MainActor (CGPoint) -> Bool

    /// 在另一格松开、落定之后执行，拿到拖动的项与目标格（移动之后的下标）
    let moveHandler: @MainActor (FolderItem, Int) -> Void
}
