import CoreGraphics
import Testing

@testable import Flotilla

// MARK: - FolderGridLayoutTests

/// 网格布局：列数规则决定面板的形状，必须与原生弹窗一致；可用尺寸决定何时收窄与滚动，单元格顺序决定 App 出现在哪里
struct FolderGridLayoutTests {
    /// 足够大的可用尺寸，不触发收窄与行数限制
    private let roomySize = CGSize(width: 10_000, height: 10_000)

    /// 单元格边长
    private let cell = FolderPanelMetrics.cellSize

    /// 列数与行数与原生实测一致：n = ⌈√c⌉，n 列与 n + 1 列取总格数少的；行数超过 5 改 7 列
    @Test(arguments: [
        (1, 1, 1),
        (2, 2, 1),
        (3, 3, 1),
        (4, 2, 2),
        (5, 3, 2),
        (6, 3, 2),
        (7, 4, 2),
        (8, 4, 2),
        (9, 3, 3),
        (10, 5, 2),
        (11, 4, 3),
        (13, 5, 3),
        (17, 6, 3),
        (20, 5, 4),
        (21, 6, 4),
        (26, 7, 4),
        (31, 7, 5),
        (36, 7, 6),
        (101, 7, 15),
    ])
    func columnsAndRowsMatchNativeGrid(
        itemCount: Int,
        columnCount: Int,
        rowCount: Int
    ) {
        let layout = FolderGridLayout(itemCount: itemCount, availableSize: roomySize)

        #expect(layout.columnCount == columnCount)
        #expect(layout.rowCount == rowCount)
    }

    /// 面板主体宽 = 128 × 列数 + 34、高 = 128 × 显示行数 + 44，与原生截图的尺寸一致
    @Test(arguments: [
        (1, CGSize(width: 162, height: 172)),
        (7, CGSize(width: 546, height: 300)),
        (9, CGSize(width: 418, height: 428)),
        (31, CGSize(width: 930, height: 684)),
    ])
    func bodySizeMatchesNativePanel(itemCount: Int, bodySize: CGSize) {
        let layout = FolderGridLayout(itemCount: itemCount, availableSize: roomySize)

        #expect(layout.bodySize == bodySize)
    }

    /// 项按行优先从左上角依次排列，单元格彼此紧贴，最后一行靠左
    @Test
    func cellsFillRowsFromTopLeftWithoutGaps() {
        let layout = FolderGridLayout(itemCount: 7, availableSize: roomySize)

        #expect(layout.cellFrames.count == 7)

        #expect(layout.cellFrames[0] == CGRect(x: 0, y: 0, width: cell, height: cell))
        #expect(layout.cellFrames[3] == CGRect(x: 3 * cell, y: 0, width: cell, height: cell))
        #expect(layout.cellFrames[4] == CGRect(x: 0, y: cell, width: cell, height: cell))
        #expect(layout.cellFrames[6] == CGRect(x: 2 * cell, y: cell, width: cell, height: cell))

        #expect(layout.gridSize == CGSize(width: 4 * cell, height: 2 * cell))
    }

    /// 最多显示 5 行：5 行时不滚动；多出一行就固定为 5 行高并滚动，网格保持完整高度
    @Test
    func scrollsBeyondFiveRows() {
        let fitting = FolderGridLayout(itemCount: 35, availableSize: roomySize)
        let overflowing = FolderGridLayout(itemCount: 36, availableSize: roomySize)

        #expect(fitting.rowCount == 5)
        #expect(!fitting.needsScrolling)

        #expect(overflowing.visibleRowCount == 5)
        #expect(overflowing.needsScrolling)
        #expect(overflowing.bodySize.height == 5 * cell + 44)
        #expect(overflowing.gridSize.height == 6 * cell)
    }

    /// 屏幕较矮时按能完整显示的行数固定高度并滚动，面板高度不超过可用高度
    @Test
    func shortScreenShowsFewerRows() {
        let availableHeight = 3.5 * cell + 44

        let layout = FolderGridLayout(
            itemCount: 31,
            availableSize: CGSize(width: roomySize.width, height: availableHeight)
        )

        #expect(layout.visibleRowCount == 3)
        #expect(layout.needsScrolling)
        #expect(layout.bodySize.height <= availableHeight)
    }

    /// 屏幕较窄时减少列数，面板宽度不超过可用宽度
    @Test
    func narrowScreenReducesColumns() {
        let availableWidth = 3.5 * cell + 34

        let layout = FolderGridLayout(
            itemCount: 10,
            availableSize: CGSize(width: availableWidth, height: roomySize.height)
        )

        #expect(layout.columnCount == 3)
        #expect(layout.rowCount == 4)
        #expect(layout.bodySize.width <= availableWidth)
    }

    /// 可用尺寸连一格都放不下时仍保留一列、显示一行
    @Test
    func keepsAtLeastOneCell() {
        let layout = FolderGridLayout(
            itemCount: 3,
            availableSize: CGSize(width: 10, height: 10)
        )

        #expect(layout.columnCount == 1)
        #expect(layout.rowCount == 3)
        #expect(layout.visibleRowCount == 1)
        #expect(layout.needsScrolling)
    }

    /// 空文件夹按 1 格的尺寸显示，与原生只有一格“在访达中打开”时相同，格内为空
    @Test
    func emptyFolderHasOneEmptyCell() {
        let layout = FolderGridLayout(itemCount: 0, availableSize: roomySize)

        #expect(layout.cellFrames.isEmpty)
        #expect(layout.bodySize == CGSize(width: 162, height: 172))
        #expect(!layout.needsScrolling)
    }
}
