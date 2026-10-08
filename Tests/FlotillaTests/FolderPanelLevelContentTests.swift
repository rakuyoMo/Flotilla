import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderPanelLevelContentTests

/// 网格的格数决定面板尺寸：访达里的文件夹末尾另有 “在访达中打开”，与原生叠放一致；
/// Flotilla 的文件夹没有这一格（需求 4）
@MainActor
struct FolderPanelLevelContentTests {
    /// 被展开的访达里的文件夹：内容由测试直接给出，不读磁盘
    private let finderFolder = FileReference(
        id: UUID(),
        url: URL(filePath: "/Users/Shared/", directoryHint: .isDirectory),
        bookmark: nil
    )

    /// 访达里的文件夹的格数是目录项数 + 1
    @Test
    func finderFolderHasOpenInFinderCell() {
        let content = FolderPanelLevelContent.finderFolder(finderFolder, items: makeFiles(3))

        #expect(content.cellCount == 4)
        #expect(content.finderFolderURL == finderFolder.url)
    }

    /// 空的访达里的文件夹只有 “在访达中打开” 一格
    @Test
    func emptyFinderFolderHasOneCell() {
        let content = FolderPanelLevelContent.finderFolder(finderFolder, items: [])

        #expect(content.cellCount == 1)
    }

    /// Flotilla 的文件夹格数就是项数，空文件夹为 0
    @Test
    func flotillaFolderHasNoOpenInFinderCell() {
        let folder = Folder(id: UUID(), name: "工作", items: makeFiles(3))
        let empty = Folder(id: UUID(), name: "空", items: [])

        #expect(FolderPanelLevelContent.folder(folder).cellCount == 3)
        #expect(FolderPanelLevelContent.folder(folder).finderFolderURL == nil)
        #expect(FolderPanelLevelContent.folder(empty).cellCount == 0)
    }

    /// 只有访达里的文件夹的层级里，文件显示内容缩略图：与原生叠放一致；Flotilla 的文件夹显示图标
    @Test
    func onlyFinderFolderShowsFileThumbnails() {
        let folder = Folder(id: UUID(), name: "工作", items: makeFiles(3))

        let finderFolderContent = FolderPanelLevelContent.finderFolder(
            finderFolder,
            items: makeFiles(3)
        )
        let folderContent = FolderPanelLevelContent.folder(folder)

        #expect(finderFolderContent.showsFileThumbnails)
        #expect(!folderContent.showsFileThumbnails)
    }

    /// 网格按格数摆出单元格：访达里的文件夹多出末尾那一格
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
    private func makeFiles(_ count: Int) -> [FolderItem] {
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
        items: [FolderItem],
        openInFinderHandler: (() -> Void)?
    ) -> FolderGridView {
        let cellCount = items.count + (openInFinderHandler == nil ? 0 : 1)

        let layout = FolderGridLayout(
            itemCount: cellCount,
            availableSize: CGSize(width: 2000, height: 2000)
        )

        let grid = FolderGridView(
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
