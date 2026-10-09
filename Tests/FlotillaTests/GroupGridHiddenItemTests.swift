import AppKit
import Testing

@testable import Flotilla

// MARK: - GroupGridHiddenItemTests

/// 访达文件夹显示隐藏文件时，隐藏的项与访达的 ⌘⇧. 一样半透明，一眼分得出哪些平时看不见；
/// 按下时照样压暗，点击的反馈不因半透明而消失
@MainActor
struct GroupGridHiddenItemTests {
    /// 两个文件：第一个是隐藏的，第二个是普通的
    private let items: [GroupItem] = [".隐藏.txt", "报告.txt"].map {
        .file(FileReference(
            id: UUID(),
            url: URL(filePath: "/Users/Shared/\($0)"),
            bookmark: nil
        ))
    }

    /// 隐藏的项图标与名称半透明，普通的项不透明
    @Test
    func hiddenItemIsTranslucent() throws {
        let cells = try makeCells()

        #expect(cells[0].alphaValue == GroupPanelMetrics.hiddenItemOpacity)
        #expect(cells[1].alphaValue == 1)
    }

    /// 按下隐藏的项：图标照样压暗，半透明不变
    @Test
    func pressedHiddenItemStillDarkens() throws {
        let hiddenCell = try makeCells()[0]
        let normalImage = try displayedImage(of: hiddenCell)

        let mouseDown = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: hiddenCell.iconCenter,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))

        hiddenCell.mouseDown(with: mouseDown)

        #expect(try displayedImage(of: hiddenCell) !== normalImage)
        #expect(hiddenCell.alphaValue == GroupPanelMetrics.hiddenItemOpacity)
    }
}

// MARK: - Private

extension GroupGridHiddenItemTests {
    /// 只把第一个文件标为隐藏的网格里，按从左到右排好的两个单元格
    private func makeCells() throws -> [GroupGridItemView] {
        let layout = GroupGridLayout(
            itemCount: items.count,
            availableSize: CGSize(width: 2000, height: 2000)
        )

        let grid = GroupGridView(
            items: items,
            layout: layout,
            previewIconCount: 0,
            hiddenItemIDs: [items[0].id],
            fileThumbnailLoader: nil,
            openInFinderHandler: nil
        ) { _ in }

        grid.layoutSubtreeIfNeeded()

        let cells = grid.subviews
            .compactMap { $0 as? GroupGridItemView }
            .sorted { $0.frame.minX < $1.frame.minX }

        try #require(cells.count == items.count)

        return cells
    }

    /// 单元格当前显示的图
    private func displayedImage(of itemView: GroupGridItemView) throws -> NSImage {
        let imageView = try #require(itemView.subviews.compactMap { $0 as? NSImageView }.first)

        return try #require(imageView.image)
    }
}
