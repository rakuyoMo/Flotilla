// MARK: - FolderGridItemStyle

/// 网格单元格的样式：决定图标怎么画、按下时怎么变、在哪里抬起才触发
enum FolderGridItemStyle {
    /// 各项与子文件夹：按下时图标压暗，拖出单元格即恢复，在单元格内抬起才触发；
    /// 文件夹的层级里按下后移动超过 `FolderPanelMetrics.dragThreshold` 即开始拖动，这次按下不再算点击
    case item

    /// 访达里的文件夹的层级末尾的 “在访达中打开”，与原生叠放相同：
    /// 图标按外观叠加到面板材质上，按下时叠加量变小；按下后保持到抬起，在哪里抬起都触发
    case openInFinder
}
