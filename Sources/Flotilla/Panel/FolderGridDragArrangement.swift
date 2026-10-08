import CoreGraphics

// MARK: - FolderGridDragArrangement

/// 拖动网格里的一项时各项所在的格：纯计算，与 `FolderGridLayout` 一样不依赖视图
///
/// 拖动的项占目标格，其余各项按 “拖动的项放到目标格” 之后的顺序让位。
/// 格按行优先从左上角排列，坐标系原点在网格左上角、y 向下
struct FolderGridDragArrangement: Equatable {
    /// 拖动的项放下后所在的格，即移动之后的下标
    let targetIndex: Int

    /// 各项所在的格，按项原来的顺序
    let cellIndices: [Int]

    /// 按目标格排出各项所在的格
    /// - Parameters:
    ///   - itemCount: 项数
    ///   - draggedIndex: 拖动的项原来的下标
    ///   - targetIndex: 目标格
    init(
        itemCount: Int,
        draggedIndex: Int,
        targetIndex: Int
    ) {
        self.targetIndex = targetIndex

        cellIndices = (0 ..< itemCount).map { (index: Int) -> Int in
            guard index != draggedIndex else { return targetIndex }

            // 去掉拖动的项之后，其余各项依次排列的位置：拖动的项之后的各项前移一格
            let position = index < draggedIndex ? index : index - 1

            // 目标格及其后的各项后移一格，空出目标格
            return position < targetIndex ? position : position + 1
        }
    }

    /// 鼠标所在的目标格
    ///
    /// 鼠标在网格的可见区域之外（标题区、两侧与底部的留白、尾巴）时，按离它最近的可见格算，露出一部分的行也算可见；
    /// 落在最后一项之后的空格，算作最后一格
    /// - Parameters:
    ///   - location: 鼠标的位置，网格坐标
    ///   - visibleRect: 网格的可见区域，网格坐标；网格滚动之后随之变化
    ///   - itemCount: 项数，至少 1
    ///   - columnCount: 列数，至少 1
    static func targetIndex(
        at location: CGPoint,
        visibleRect: CGRect,
        itemCount: Int,
        columnCount: Int
    ) -> Int {
        let cell = FolderPanelMetrics.cellSize
        let rowCount = (itemCount + columnCount - 1) / columnCount

        let gridBounds = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(columnCount) * cell,
            height: CGFloat(rowCount) * cell
        )

        // 可见区域限在网格之内；滚动视图比网格宽，可见区域可能伸到网格右边之外
        let visibleArea = visibleRect.intersection(gridBounds)
        let area = visibleArea.isEmpty ? gridBounds : visibleArea

        // 鼠标所在的行与列，夹到可见区域覆盖的行与列之内，即离它最近的可见格
        let column = clamp(
            Int((location.x / cell).rounded(.down)),
            from: Int((area.minX / cell).rounded(.down)),
            to: Int((area.maxX / cell).rounded(.up)) - 1
        )

        let row = clamp(
            Int((location.y / cell).rounded(.down)),
            from: Int((area.minY / cell).rounded(.down)),
            to: Int((area.maxY / cell).rounded(.up)) - 1
        )

        return min(row * columnCount + column, itemCount - 1)
    }

    /// 交给 `FolderStore.move(itemID:to:at:)` 的下标
    ///
    /// `move` 的下标按移动前计算、同层向后移动时它自己减一，因此向后移动要多加一
    /// - Parameters:
    ///   - sourceIndex: 拖动的项原来的下标
    ///   - targetIndex: 目标格，即移动之后的下标
    static func moveIndex(from sourceIndex: Int, to targetIndex: Int) -> Int {
        targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
    }
}

// MARK: - Helpers

extension FolderGridDragArrangement {
    /// 把值夹到闭区间之内
    private static func clamp(
        _ value: Int,
        from lowerBound: Int,
        to upperBound: Int
    ) -> Int {
        min(max(value, lowerBound), upperBound)
    }
}
