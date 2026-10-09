import AppKit
import Testing

@testable import Flotilla

// MARK: - GroupPanelLevelContentTests

/// 网格的格数决定面板尺寸：访达文件夹末尾另有 “在访达中打开”，与原生叠放一致；
/// 组没有这一格（需求 4）
@MainActor
struct GroupPanelLevelContentTests {
    /// 被展开的访达文件夹：内容由测试直接给出，不读磁盘
    private let finderFolder = FileReference(
        id: UUID(),
        url: URL(filePath: "/Users/Shared/", directoryHint: .isDirectory),
        bookmark: nil
    )

    /// 访达文件夹的格数是目录项数 + 1
    @Test
    func finderFolderHasOpenInFinderCell() {
        let content = GroupPanelLevelContent.finderFolder(finderFolder, items: makeFiles(3))

        #expect(content.cellCount == 4)
        #expect(content.finderFolderURL == finderFolder.url)
    }

    /// 空的访达文件夹只有 “在访达中打开” 一格
    @Test
    func emptyFinderFolderHasOneCell() {
        let content = GroupPanelLevelContent.finderFolder(finderFolder, items: [])

        #expect(content.cellCount == 1)
    }

    /// 组的格数就是项数，空组为 0
    @Test
    func flotillaGroupHasNoOpenInFinderCell() {
        let group = Group(id: UUID(), name: "工作", items: makeFiles(3))
        let empty = Group(id: UUID(), name: "空", items: [])

        #expect(GroupPanelLevelContent.group(group).cellCount == 3)
        #expect(GroupPanelLevelContent.group(group).finderFolderURL == nil)
        #expect(GroupPanelLevelContent.group(empty).cellCount == 0)
    }

    /// 只有访达文件夹的层级里，文件显示内容缩略图：与原生叠放一致；组里的文件显示图标
    @Test
    func onlyFinderFolderShowsFileThumbnails() {
        let group = Group(id: UUID(), name: "工作", items: makeFiles(3))

        let finderFolderContent = GroupPanelLevelContent.finderFolder(
            finderFolder,
            items: makeFiles(3)
        )
        let groupContent = GroupPanelLevelContent.group(group)

        #expect(finderFolderContent.showsFileThumbnails)
        #expect(!groupContent.showsFileThumbnails)
    }

    /// 网格按格数摆出单元格：访达文件夹多出末尾那一格
    @Test
    func gridViewAddsOpenInFinderCell() {
        let items = makeFiles(2)

        let withCell = makeGridView(items: items, openInFinderHandler: { })
        let withoutCell = makeGridView(items: items, openInFinderHandler: nil)

        #expect(withCell.subviews.count == 3)
        #expect(withoutCell.subviews.count == 2)
    }

    /// `count` 个文件项；
    /// 路径不必存在，这里只数格数
    private func makeFiles(_ count: Int) -> [GroupItem] {
        (0 ..< count).map {
            .file(FileReference(
                id: UUID(),
                url: URL(filePath: "/Users/Shared/文件\($0).txt"),
                bookmark: nil
            ))
        }
    }

    /// 按格数建一个网格并排好版：不在滚动视图里时整个网格都算看得见，单元格全部建出
    private func makeGridView(
        items: [GroupItem],
        openInFinderHandler: (() -> Void)?
    ) -> GroupGridView {
        let cellCount = items.count + (openInFinderHandler == nil ? 0 : 1)

        let layout = GroupGridLayout(
            itemCount: cellCount,
            availableSize: CGSize(width: 2000, height: 2000)
        )

        let grid = GroupGridView(
            items: items,
            layout: layout,
            previewIconCount: 0,
            hiddenItemIDs: [],
            fileThumbnailLoader: nil,
            openInFinderHandler: openInFinderHandler
        ) { _ in }

        grid.layoutSubtreeIfNeeded()

        return grid
    }
}
