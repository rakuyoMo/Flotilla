import CoreGraphics
import Foundation

// MARK: - FolderGridLayout

/// 网格的纯几何计算：列数、行数、每个单元格的位置、面板主体尺寸，以及是否需要滚动
struct FolderGridLayout: Equatable {
    #warning("TODO: 待实测 列数规则、单元格 112×100、内边距 16、导航头高度 32、滚动阈值")

    /// 列数；空文件夹为 0
    let columnCount: Int

    /// 行数；空文件夹为 0
    let rowCount: Int

    /// 每一项的单元格，顺序与项的顺序一致；坐标系原点在网格左上角、y 向下
    let cellFrames: [CGRect]

    /// 网格内容的完整尺寸，即全部单元格的外接矩形
    let gridSize: CGSize

    /// 面板主体（不含尾巴）的尺寸：网格加内边距，有导航头时再加导航头；需要滚动时高度固定为可用高度
    let panelSize: CGSize

    /// 网格高度超出可用高度，需要放进滚动视图
    let needsScrolling: Bool

    /// 计算网格布局
    /// - Parameters:
    ///   - itemCount: 项数
    ///   - availableSize: 面板主体可用的最大尺寸，见 `FolderPanelPlacement.availableBodySize`
    ///   - hasHeader: 是否显示导航头
    init(itemCount: Int, availableSize: CGSize, hasHeader: Bool) {
        let cellSize = FolderPanelMetrics.cellSize
        let inset = FolderPanelMetrics.contentInset
        let headerHeight = hasHeader ? FolderPanelMetrics.headerHeight : 0

        let columnCount = Self.columnCount(
            itemCount: itemCount,
            availableWidth: availableSize.width - 2 * inset,
            cellWidth: cellSize.width
        )
        let rowCount = columnCount > 0 ? (itemCount + columnCount - 1) / columnCount : 0

        // 按行优先从左上角依次排列，最后一行靠左
        let cellFrames = (0 ..< itemCount).map {
            CGRect(
                x: CGFloat($0 % columnCount) * cellSize.width,
                y: CGFloat($0 / columnCount) * cellSize.height,
                width: cellSize.width,
                height: cellSize.height
            )
        }
        let gridSize = CGSize(
            width: CGFloat(columnCount) * cellSize.width,
            height: CGFloat(rowCount) * cellSize.height
        )

        // 自然高度超出可用高度时固定为可用高度，多出的部分靠滚动查看
        let naturalHeight = gridSize.height + 2 * inset + headerHeight
        let needsScrolling = naturalHeight > availableSize.height

        self.columnCount = columnCount
        self.rowCount = rowCount
        self.cellFrames = cellFrames
        self.gridSize = gridSize
        self.needsScrolling = needsScrolling
        panelSize = CGSize(
            width: gridSize.width + 2 * inset,
            height: needsScrolling ? availableSize.height : naturalHeight
        )
    }
}

// MARK: - Private

extension FolderGridLayout {
    /// 列数：`min(项数, max(最少列数, ceil(sqrt(项数 × 系数))))`，再受可用宽度限制，至少 1 列
    private static func columnCount(itemCount: Int, availableWidth: CGFloat, cellWidth: CGFloat) -> Int {
        guard itemCount > 0 else { return 0 }

        let growth = Int((Double(itemCount) * FolderPanelMetrics.columnGrowthFactor).squareRoot().rounded(.up))
        let preferred = min(itemCount, max(FolderPanelMetrics.minimumColumnCount, growth))

        // 屏幕放不下时减少列数，宽度不超过屏幕
        let fitting = Int((availableWidth / cellWidth).rounded(.down))
        return max(1, min(preferred, fitting))
    }
}
