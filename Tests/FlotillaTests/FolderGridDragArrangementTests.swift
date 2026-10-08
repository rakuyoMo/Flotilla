import CoreGraphics
import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderGridDragArrangementTests

/// 拖动时的目标格与各项的格决定了松开前看到的顺序：保存下来的顺序必须与之相同，
/// 鼠标离开网格的可见区域时也要有确定的目标
@MainActor
final class FolderGridDragArrangementTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 单元格边长
    private let cell = FolderPanelMetrics.cellSize

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: 目标格

    /// 鼠标在某一格上：目标就是这一格
    @Test
    func targetIsCellUnderMouse() {
        let visibleRect = CGRect(x: 0, y: 0, width: 3 * cell, height: 2 * cell)

        #expect(target(at: point(column: 2, row: 1), visibleRect: visibleRect) == 5)
        #expect(target(at: point(column: 0, row: 0), visibleRect: visibleRect) == 0)
    }

    /// 鼠标在标题区（可见区域上方）：取第一个可见行里同一列的格
    @Test
    func headerMapsToFirstVisibleRow() {
        let visibleRect = CGRect(x: 0, y: 0, width: 3 * cell, height: 2 * cell)
        let header = CGPoint(x: 2.5 * cell, y: -20)

        #expect(target(at: header, visibleRect: visibleRect) == 2)
    }

    /// 鼠标在两侧留白、底部留白与尾巴：按离它最近的可见格算
    @Test
    func marginsMapToNearestVisibleCell() {
        let visibleRect = CGRect(x: 0, y: 0, width: 3 * cell, height: 2 * cell)

        let leftMargin = CGPoint(x: -10, y: 1.5 * cell)
        let rightMargin = CGPoint(x: 3 * cell + 10, y: 0.5 * cell)
        let tail = CGPoint(x: 1.5 * cell, y: 2 * cell + 40)

        #expect(target(at: leftMargin, visibleRect: visibleRect) == 3)
        #expect(target(at: rightMargin, visibleRect: visibleRect) == 2)
        #expect(target(at: tail, visibleRect: visibleRect) == 4)
    }

    /// 最后一项之后的空格算作最后一格：5 项排成 3 列时，第二行最右边那一格是空的
    @Test
    func emptyCellAfterLastItemMapsToLastItem() {
        let visibleRect = CGRect(x: 0, y: 0, width: 3 * cell, height: 2 * cell)

        let index = FolderGridDragArrangement.targetIndex(
            at: point(column: 2, row: 1),
            visibleRect: visibleRect,
            itemCount: 5,
            columnCount: 3
        )

        #expect(index == 4)
    }

    /// 网格滚动之后，标题区与尾巴对应的是滚动后的第一个与最后一个可见行；露出一部分的行也算可见
    @Test
    func scrolledGridMapsToScrolledRows() {
        // 7 列、6 行，显示 5 行，向下滚了一行半
        let scrolled = CGRect(x: 0, y: 1.5 * cell, width: 7 * cell, height: 5 * cell)

        let header = CGPoint(x: 3.5 * cell, y: scrolled.minY - 20)
        let tail = CGPoint(x: 3.5 * cell, y: scrolled.maxY + 40)

        let headerTarget = FolderGridDragArrangement.targetIndex(
            at: header,
            visibleRect: scrolled,
            itemCount: 40,
            columnCount: 7
        )

        let tailTarget = FolderGridDragArrangement.targetIndex(
            at: tail,
            visibleRect: scrolled,
            itemCount: 40,
            columnCount: 7
        )

        #expect(headerTarget == 7 + 3)
        #expect(tailTarget == 35 + 3)
    }

    // MARK: 各项的格

    /// 轮廓之内向后拖：中间的项前移一格，空位在目标格
    @Test
    func itemsMakeRoomWhenDraggedForward() {
        let arrangement = FolderGridDragArrangement(
            itemCount: 6,
            draggedIndex: 1,
            targetIndex: 4
        )

        #expect(arrangement.cellIndices == [0, 4, 1, 2, 3, 5])
    }

    /// 轮廓之内向前拖：中间的项后移一格，空位在目标格
    @Test
    func itemsMakeRoomWhenDraggedBackward() {
        let arrangement = FolderGridDragArrangement(
            itemCount: 6,
            draggedIndex: 4,
            targetIndex: 1
        )

        #expect(arrangement.cellIndices == [0, 2, 3, 4, 1, 5])
    }

    // MARK: 交给 `FolderStore` 的下标

    /// 向前、向后与原地松开：按换算出的下标移动之后，文件夹里的顺序与松开前网格显示的顺序相同
    @Test
    func storeOrderMatchesDisplayedOrder() throws {
        let cases = [(1, 4), (0, 5), (2, 3), (4, 1), (5, 0), (3, 2), (2, 2)]

        for (sourceIndex, targetIndex) in cases {
            let fileURL = directory.appending(path: "\(UUID().uuidString).json")
            let store = FolderStore(fileURL: fileURL)
            let folder = store.addRootFolder(named: "根")

            store.addItems(try webPages(count: 6), to: folder.id)

            let items = try #require(store.folder(id: folder.id)).items

            let arrangement = FolderGridDragArrangement(
                itemCount: items.count,
                draggedIndex: sourceIndex,
                targetIndex: targetIndex
            )

            store.move(
                itemID: items[sourceIndex].id,
                to: folder.id,
                at: FolderGridDragArrangement.moveIndex(from: sourceIndex, to: targetIndex)
            )

            let saved = try #require(store.folder(id: folder.id)).items

            #expect(
                saved.map(\.id) == displayedOrder(of: items, in: arrangement),
                "从 \(sourceIndex) 拖到 \(targetIndex)"
            )
        }
    }
}

// MARK: - Private

extension FolderGridDragArrangementTests {
    /// 3 列、6 项的网格里鼠标所在的目标格
    private func target(at location: CGPoint, visibleRect: CGRect) -> Int {
        FolderGridDragArrangement.targetIndex(
            at: location,
            visibleRect: visibleRect,
            itemCount: 6,
            columnCount: 3
        )
    }

    /// 某一格的中心，网格坐标
    private func point(column: Int, row: Int) -> CGPoint {
        CGPoint(
            x: (CGFloat(column) + 0.5) * cell,
            y: (CGFloat(row) + 0.5) * cell
        )
    }

    /// 网格按排列显示的各项 id，按格的先后
    private func displayedOrder(
        of items: [FolderItem],
        in arrangement: FolderGridDragArrangement
    ) -> [UUID] {
        zip(items, arrangement.cellIndices)
            .sorted { $0.1 < $1.1 }
            .map(\.0.id)
    }

    /// 网址各不相同的网页：同一文件夹里按网址去重，网址相同的不会都加进去
    private func webPages(count: Int) throws -> [FolderItem] {
        try (0 ..< count).map {
            .webPage(WebPageReference(
                id: UUID(),
                url: try #require(URL(string: "https://example.com/\($0)")),
                title: "网页\($0)"
            ))
        }
    }
}
