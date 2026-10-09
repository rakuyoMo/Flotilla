import QuartzCore

// MARK: - FolderGridDragAnimation

/// 拖动时的位置动画：其余各格让位、补位与拖动图像落进目标格共用一种，拖动图像落回原来的格另用一种
///
/// 原生 Dock 文件夹不能拖动排序，没有可对照的行为，让位、补位与落进目标格的时长与曲线沿用展开动画；
/// 落回原来的格照抄程序坞里提前松手时图标飞回原位的时长与曲线
@MainActor
enum FolderGridDragAnimation {
    /// 让位、补位与落进目标格：图层从画面上的 `start` 移到它现在的模型位置，时长与曲线沿用展开动画
    ///
    /// 动画途中目标又变时，调用方传入当前画面上的位置（`presentation()`），从那里接着移动，不跳、不闪
    /// - Parameters:
    ///   - layer: 模型位置已经设好的图层
    ///   - start: 动画开始时画面上的位置，与 `position` 同一坐标系
    static func movePosition(of layer: CALayer, from start: CGPoint) {
        let controlPoints = FolderPanelMetrics.expandTimingControlPoints

        addPositionAnimation(
            to: layer,
            from: start,
            duration: FolderPanelMetrics.expandDuration,
            timing: CAMediaTimingFunction(
                controlPoints: controlPoints[0],
                controlPoints[1],
                controlPoints[2],
                controlPoints[3]
            )
        )
    }

    /// 落回原来的格：图层从画面上的 `start` 移到它现在的模型位置，时长 `returnDuration`，两头慢、中间快
    /// - Parameters:
    ///   - layer: 模型位置已经设好的图层
    ///   - start: 动画开始时画面上的位置，与 `position` 同一坐标系
    static func returnPosition(of layer: CALayer, from start: CGPoint) {
        addPositionAnimation(
            to: layer,
            from: start,
            duration: FolderPanelMetrics.returnDuration,
            timing: CAMediaTimingFunction(name: .easeInEaseOut)
        )
    }
}

// MARK: - Private

extension FolderGridDragAnimation {
    /// 给图层加上从 `start` 到模型位置的 `position` 动画
    private static func addPositionAnimation(
        to layer: CALayer,
        from start: CGPoint,
        duration: CFTimeInterval,
        timing: CAMediaTimingFunction
    ) {
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = NSValue(point: start)
        animation.toValue = NSValue(point: layer.position)
        animation.duration = duration
        animation.timingFunction = timing

        // 同一个键替换掉进行中的动画：起点已是那段动画当前的画面
        layer.add(animation, forKey: "position")
    }
}
