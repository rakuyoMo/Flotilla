import AppKit

// MARK: - FolderGridDragSession

/// 网格里的一次拖动：从开始拖动到落定，或到删除、作废为止
@MainActor
struct FolderGridDragSession {
    /// 拖动的项原来的下标
    let itemIndex: Int

    /// 拖动的项的单元格：拖动期间图标与名称隐藏，原处留出空位
    let itemView: FolderGridItemView

    /// 图标中心相对鼠标的偏移，屏幕坐标：保持按下时两者的相对位置
    let iconOffset: CGVector

    /// 跟随鼠标的拖动图像
    let image: FolderGridDragImage

    /// 鼠标最近一次的位置，窗口坐标；网格滚动之后按它重新判定目标格
    var location: CGPoint

    /// 当前各项所在的格
    var arrangement: FolderGridDragArrangement

    /// 是否已在轮廓之内松开、拖动图像正落进目标格：这期间网格不响应新的按下
    var isLanding = false
}
