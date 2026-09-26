import CoreGraphics
import Testing

@testable import Flotilla

// MARK: - FolderGridLayoutTests

/// 网格布局：列数规则决定面板的形状，可用尺寸决定何时收窄与滚动，单元格顺序决定 App 出现在哪里
struct FolderGridLayoutTests {
    /// 足够大的可用尺寸，不触发收窄与滚动
    private let roomySize = CGSize(width: 10_000, height: 10_000)

    /// 列数按 `min(项数, max(4, ceil(sqrt(项数 × 1.5))))`，行数按列数向上取整
    @Test(arguments: [
        (1, 1, 1),
        (2, 2, 1),
        (3, 3, 1),
        (4, 4, 1),
        (5, 4, 2),
        (6, 4, 2),
        (7, 4, 2),
        (9, 4, 3),
        (12, 5, 3),
        (16, 5, 4),
        (20, 6, 4),
        (30, 7, 5),
    ])
    func columnsAndRowsFollowRule(itemCount: Int, columnCount: Int, rowCount: Int) {
        let layout = FolderGridLayout(itemCount: itemCount, availableSize: roomySize, hasHeader: false)

        #expect(layout.columnCount == columnCount)
        #expect(layout.rowCount == rowCount)
        #expect(!layout.needsScrolling)
    }

    /// 项按行优先从左上角依次排列，最后一行靠左
    @Test
    func cellsFillRowsFromTopLeft() {
        let cell = FolderPanelMetrics.cellSize
        let layout = FolderGridLayout(itemCount: 6, availableSize: roomySize, hasHeader: false)

        #expect(layout.cellFrames.count == 6)
        #expect(layout.cellFrames[0] == CGRect(origin: .zero, size: cell))
        #expect(layout.cellFrames[3] == CGRect(x: 3 * cell.width, y: 0, width: cell.width, height: cell.height))
        #expect(layout.cellFrames[4] == CGRect(x: 0, y: cell.height, width: cell.width, height: cell.height))
        #expect(layout.cellFrames[5] == CGRect(x: cell.width, y: cell.height, width: cell.width, height: cell.height))
    }

    /// 面板主体 = 网格 + 两侧内边距；导航头只增加高度
    @Test(arguments: [false, true])
    func panelSizeWrapsGridWithInsets(hasHeader: Bool) {
        let cell = FolderPanelMetrics.cellSize
        let inset = FolderPanelMetrics.contentInset
        let header = hasHeader ? FolderPanelMetrics.headerHeight : 0

        let layout = FolderGridLayout(itemCount: 9, availableSize: roomySize, hasHeader: hasHeader)

        #expect(layout.gridSize == CGSize(width: 4 * cell.width, height: 3 * cell.height))
        #expect(layout.panelSize == CGSize(
            width: 4 * cell.width + 2 * inset,
            height: 3 * cell.height + 2 * inset + header
        ))
    }

    /// 屏幕放不下规则给出的列数时减少列数，面板宽度不超过可用宽度
    @Test
    func narrowScreenReducesColumns() {
        let cell = FolderPanelMetrics.cellSize
        let inset = FolderPanelMetrics.contentInset
        let availableWidth = 3.5 * cell.width + 2 * inset

        let layout = FolderGridLayout(
            itemCount: 9,
            availableSize: CGSize(width: availableWidth, height: roomySize.height),
            hasHeader: false
        )

        #expect(layout.columnCount == 3)
        #expect(layout.rowCount == 3)
        #expect(layout.panelSize.width <= availableWidth)
    }

    /// 可用宽度连一列都放不下时仍保留一列
    @Test
    func keepsAtLeastOneColumn() {
        let layout = FolderGridLayout(
            itemCount: 3,
            availableSize: CGSize(width: 10, height: roomySize.height),
            hasHeader: false
        )

        #expect(layout.columnCount == 1)
        #expect(layout.rowCount == 3)
    }

    /// 自然高度超出可用高度时需要滚动：面板高度固定为可用高度，网格保持完整高度供滚动
    @Test
    func tallGridScrollsWithinAvailableHeight() {
        let cell = FolderPanelMetrics.cellSize
        let availableHeight: CGFloat = 400

        let layout = FolderGridLayout(
            itemCount: 30,
            availableSize: CGSize(width: roomySize.width, height: availableHeight),
            hasHeader: false
        )

        #expect(layout.needsScrolling)
        #expect(layout.panelSize.height == availableHeight)
        #expect(layout.gridSize.height == 5 * cell.height)
    }

    /// 自然高度恰好等于可用高度时不滚动；多出 1 pt 就滚动
    @Test
    func scrollingThresholdIsNaturalHeight() {
        let natural = FolderGridLayout(itemCount: 9, availableSize: roomySize, hasHeader: true).panelSize.height

        let fitting = FolderGridLayout(
            itemCount: 9,
            availableSize: CGSize(width: roomySize.width, height: natural),
            hasHeader: true
        )
        let overflowing = FolderGridLayout(
            itemCount: 9,
            availableSize: CGSize(width: roomySize.width, height: natural - 1),
            hasHeader: true
        )

        #expect(!fitting.needsScrolling)
        #expect(overflowing.needsScrolling)
    }

    /// 空文件夹只有内边距（与导航头）构成的最小面板
    @Test(arguments: [false, true])
    func emptyFolderIsMinimalPanel(hasHeader: Bool) {
        let inset = FolderPanelMetrics.contentInset
        let header = hasHeader ? FolderPanelMetrics.headerHeight : 0

        let layout = FolderGridLayout(itemCount: 0, availableSize: roomySize, hasHeader: hasHeader)

        #expect(layout.columnCount == 0)
        #expect(layout.rowCount == 0)
        #expect(layout.cellFrames.isEmpty)
        #expect(layout.panelSize == CGSize(width: 2 * inset, height: 2 * inset + header))
        #expect(!layout.needsScrolling)
    }
}
