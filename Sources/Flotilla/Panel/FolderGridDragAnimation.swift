import QuartzCore

// MARK: - FolderGridDragAnimation

/// 拖动时的位置动画：其余各格让位、补位，与拖动图像落进目标格共用
///
/// 原生 Dock 文件夹不能拖动排序，没有可对照的行为，时长与曲线沿用展开动画
@MainActor
enum FolderGridDragAnimation {
    /// 图层从画面上的 `start` 移到它现在的模型位置
    ///
    /// 动画途中目标又变时，调用方传入当前画面上的位置（`presentation()`），从那里接着移动，不跳、不闪
    /// - Parameters:
    ///   - layer: 模型位置已经设好的图层
    ///   - start: 动画开始时画面上的位置，与 `position` 同一坐标系
    static func movePosition(of layer: CALayer, from start: CGPoint) {
        let controlPoints = FolderPanelMetrics.expandTimingControlPoints

        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: start)
        animation.toValue = NSValue(point: layer.position)
        animation.duration = FolderPanelMetrics.expandDuration

        animation.timingFunction = CAMediaTimingFunction(
            controlPoints: controlPoints[0],
            controlPoints[1],
            controlPoints[2],
            controlPoints[3]
        )

        // 同一个键替换掉进行中的动画：起点已是那段动画当前的画面
        layer.add(animation, forKey: "position")
    }
}
