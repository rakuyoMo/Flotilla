import CoreGraphics

// MARK: - FolderGridLayout

/// 网格的纯几何计算：列数、行数、每个单元格的位置、面板主体尺寸，以及是否需要滚动
///
/// 面板主体自上而下是标题区与网格，根层级与子层级相同
struct FolderGridLayout {
    /// 列数；没有格时为 0
    let columnCount: Int

    /// 全部项占用的行数；没有格时为 0
    let rowCount: Int

    /// 面板里显示的行数，其余行靠滚动查看；没有格时按 1 行计
    let visibleRowCount: Int

    /// 每一项的单元格，顺序与项的顺序一致；坐标系原点在网格左上角、y 向下
    let cellFrames: [CGRect]

    /// 网格内容的完整尺寸，即全部单元格的外接矩形
    let gridSize: CGSize

    /// 面板主体（不含尾巴）的尺寸：标题区、显示的行与四周留白；
    /// 没有格时按 1 格计
    let bodySize: CGSize

    /// 全部项占用的行数多于显示的行数，网格需要滚动
    let needsScrolling: Bool

    /// 计算网格布局
    /// - Parameters:
    ///   - itemCount: 格数：各项，访达里的文件夹另加末尾的“在访达中打开”
    ///   - availableSize: 面板主体可用的最大尺寸，见 `FolderPanelPlacement.availableBodySize`
    init(itemCount: Int, availableSize: CGSize) {
        let cell = FolderPanelMetrics.cellSize
        let horizontalPadding = 2 * FolderPanelMetrics.gridSideInset
        let verticalPadding = FolderPanelMetrics.headerHeight + FolderPanelMetrics.gridBottomInset

        // 屏幕放不下规则给出的列数时减少列数，至少保留 1 列
        let availableGridWidth = availableSize.width - horizontalPadding
        let fittingColumnCount = Int((availableGridWidth / cell).rounded(.down))
        let columnCount = min(
            Self.preferredColumnCount(itemCount: itemCount),
            max(1, fittingColumnCount)
        )

        let rowCount = Self.rowCount(itemCount: itemCount, columnCount: columnCount)

        // 最多显示 5 行，屏幕更矮时显示能完整放下的行数，至少 1 行
        let availableGridHeight = availableSize.height - verticalPadding
        let fittingRowCount = Int((availableGridHeight / cell).rounded(.down))
        let visibleRowCount = max(
            1,
            min(rowCount, FolderPanelMetrics.maximumVisibleRowCount, fittingRowCount)
        )

        // 按行优先从左上角依次排列，最后一行靠左
        cellFrames = (0 ..< itemCount).map {
            CGRect(
                x: CGFloat($0 % columnCount) * cell,
                y: CGFloat($0 / columnCount) * cell,
                width: cell,
                height: cell
            )
        }

        self.columnCount = columnCount
        self.rowCount = rowCount
        self.visibleRowCount = visibleRowCount

        gridSize = CGSize(
            width: CGFloat(columnCount) * cell,
            height: CGFloat(rowCount) * cell
        )

        needsScrolling = rowCount > visibleRowCount

        bodySize = CGSize(
            width: CGFloat(max(columnCount, 1)) * cell + horizontalPadding,
            height: CGFloat(visibleRowCount) * cell + verticalPadding
        )
    }
}

// MARK: - Private

extension FolderGridLayout {
    /// 规则给出的列数（c 为项数）
    ///
    /// 取 n = ⌈√c⌉，n 列与 n + 1 列中总格数更少的一个，相同时取 n 列；行数超过上限时改用固定的列数
    private static func preferredColumnCount(itemCount: Int) -> Int {
        guard itemCount > 0 else { return 0 }

        let n = Int(Double(itemCount).squareRoot().rounded(.up))
        let cellCount = { (columnCount: Int) in
            columnCount * rowCount(itemCount: itemCount, columnCount: columnCount)
        }

        let columnCount = cellCount(n) <= cellCount(n + 1) ? n : n + 1

        let preferredRowCount = rowCount(itemCount: itemCount, columnCount: columnCount)

        guard preferredRowCount > FolderPanelMetrics.maximumVisibleRowCount else {
            return columnCount
        }

        return FolderPanelMetrics.overflowColumnCount
    }

    /// 按列数排满全部项需要的行数
    private static func rowCount(itemCount: Int, columnCount: Int) -> Int {
        columnCount > 0 ? (itemCount + columnCount - 1) / columnCount : 0
    }
}
