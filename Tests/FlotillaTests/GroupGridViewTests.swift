import AppKit
import Testing

@testable import Flotilla

// MARK: - GroupGridViewTests

/// 网格只为看得见的行建单元格：访达文件夹有上千项时，一次建齐会让展开卡上几秒；
/// 同时滚动到哪里都不能露出空白格，缩回动画也要在目标格还没建时找得到它
@MainActor
struct GroupGridViewTests {
    /// 100 项加 “在访达中打开”：7 列、15 行，面板显示 5 行
    private let items: [GroupItem] = (0 ..< 100).map {
        .file(FileReference(
            id: UUID(),
            url: URL(filePath: "/Users/Shared/文件\($0).txt"),
            bookmark: nil
        ))
    }

    /// 与网格同一套布局
    private var layout: GroupGridLayout {
        GroupGridLayout(
            itemCount: items.count + 1,
            availableSize: CGSize(width: 2000, height: 2000)
        )
    }

    /// 初始停在顶部：只建显示的 5 行与其下一行
    @Test
    func buildsOnlyVisibleRows() {
        let (scrollView, grid) = makeScrolledGrid()

        scrollView.layoutSubtreeIfNeeded()

        #expect(layout.rowCount == 15)
        #expect(builtRows(of: grid) == Set(0 ... 5))
    }

    /// 滚动后同步补建新露出的行与上下各一行，已建的行保留
    @Test
    func buildsNewlyExposedRowsWhenScrolling() {
        let (scrollView, grid) = makeScrolledGrid()

        scrollView.layoutSubtreeIfNeeded()
        scroll(scrollView, toRow: 8)

        #expect(builtRows(of: grid) == Set(0 ... 5).union(7 ... 13))
    }

    /// 恢复的滚动位置在第一次排版之前生效：只建那里的行，顶部的行不建
    @Test
    func restoredScrollPositionBuildsThoseRows() {
        let (scrollView, grid) = makeScrolledGrid()

        scroll(scrollView, toRow: 8)
        scrollView.layoutSubtreeIfNeeded()

        #expect(builtRows(of: grid) == Set(7 ... 13))
    }

    /// AppKit 提前准备的区域（滚动时的预绘区域）同样建好单元格，上下各多一行
    @Test
    func preparedContentBuildsThoseRows() {
        let (_, grid) = makeScrolledGrid()
        let cell = GroupPanelMetrics.cellSize

        // 第 10、11 两行
        grid.prepareContent(in: CGRect(
            x: 0,
            y: 10 * cell,
            width: grid.bounds.width,
            height: 2 * cell
        ))

        #expect(builtRows(of: grid) == Set(9 ... 12))
    }

    /// 没建的格也按布局给出图标中心，与建好后单元格里的图标中心一致
    @Test
    func iconCenterDoesNotNeedBuiltCell() throws {
        let (scrollView, grid) = makeScrolledGrid()
        let lastItem = try #require(items.last)
        let frame = layout.cellFrames[items.count - 1]

        let center = try #require(grid.iconCenter(of: lastItem.id))

        let layoutCenter = CGPoint(
            x: frame.midX,
            y: frame.minY + GroupPanelMetrics.iconCenterY
        )

        #expect(grid.subviews.isEmpty)
        #expect(center == layoutCenter)

        // 滚到最后一行建出这一格，单元格里的图标中心就是之前按布局算出的位置
        scroll(scrollView, toRow: layout.rowCount - 1)

        let itemView = try #require(cellView(of: grid, at: frame))

        #expect(itemView.convert(itemView.iconCenter, to: grid) == center)
    }

    /// “在访达中打开” 排在最后一格，那一行露出时才建
    @Test
    func openInFinderCellIsBuiltWhenItsRowAppears() {
        let (scrollView, grid) = makeScrolledGrid()
        let frame = layout.cellFrames[items.count]

        scrollView.layoutSubtreeIfNeeded()

        #expect(cellView(of: grid, at: frame) == nil)

        scroll(scrollView, toRow: layout.rowCount - 1)

        #expect(cellView(of: grid, at: frame) != nil)
    }
}

// MARK: - Private

extension GroupGridViewTests {
    /// 与面板相同的摆法：网格作为滚动视图的文档视图，滚动视图高度正好是显示的行数
    private func makeScrolledGrid() -> (scrollView: NSScrollView, grid: GroupGridView) {
        let layout = layout

        let scrollView = NSScrollView(frame: CGRect(
            x: 0,
            y: 0,
            width: layout.gridSize.width,
            height: CGFloat(layout.visibleRowCount) * GroupPanelMetrics.cellSize
        ))

        let grid = GroupGridView(
            items: items,
            layout: layout,
            previewIconCount: 0,
            hiddenItemIDs: [],
            fileThumbnailLoader: nil,
            openInFinderHandler: { }
        ) { _ in }

        scrollView.documentView = grid

        return (scrollView, grid)
    }

    /// 让第 `row` 行（从 0 数）停在可见区域顶部，滚动视图允许的范围之外时停在最底部
    private func scroll(_ scrollView: NSScrollView, toRow row: Int) {
        let clipView = scrollView.contentView

        let proposedBounds = CGRect(
            origin: CGPoint(x: 0, y: CGFloat(row) * GroupPanelMetrics.cellSize),
            size: clipView.bounds.size
        )

        clipView.scroll(to: clipView.constrainBoundsRect(proposedBounds).origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    /// 已建单元格所在的行
    private func builtRows(of grid: GroupGridView) -> Set<Int> {
        Set(grid.subviews.map {
            Int($0.frame.minY / GroupPanelMetrics.cellSize)
        })
    }

    /// 摆在某一格上的单元格；还没建时为 nil
    private func cellView(of grid: GroupGridView, at frame: CGRect) -> GroupGridItemView? {
        grid.subviews
            .compactMap { $0 as? GroupGridItemView }
            .first { $0.frame == frame }
    }
}
