import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderPanelDragActionsTests

/// 面板只让 Flotilla 的文件夹的层级拖动：网格交出的目标格要换算成数据源的下标，保存下来的顺序才与松开前看到的相同
@MainActor
final class FolderPanelDragActionsTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 访达里的文件夹的层级没有拖动的动作，其中各项不能拖动
    @Test
    func finderFolderLevelHasNoDragActions() {
        let store = FolderStore(fileURL: directory.appending(path: "folders.json"))

        let finderFolder = FileReference(
            id: UUID(),
            url: URL(filePath: "/Users/Shared/", directoryHint: .isDirectory),
            bookmark: nil
        )

        let actions = FolderPanelController.dragActions(
            for: .finderFolder(finderFolder, items: []),
            in: store
        ) { _ in true }

        #expect(actions == nil)
    }

    /// 向后、向前与原地：保存回调按目标格移动之后，文件夹里的顺序就是 “拖动的项放到目标格” 之后的顺序
    @Test
    func moveHandlerSavesDisplayedOrder() throws {
        let cases = [(0, 3), (1, 2), (3, 0), (2, 1), (1, 1)]

        for (sourceIndex, targetIndex) in cases {
            let fileURL = directory.appending(path: "\(UUID().uuidString).json")
            let store = FolderStore(fileURL: fileURL)
            let root = store.addRootFolder(named: "根")

            store.addItems(try webPages(count: 4), to: root.id)

            let folder = try #require(store.folder(id: root.id))
            let actions = try dragActions(for: folder, in: store)

            var expected = folder.items.map(\.id)
            expected.insert(expected.remove(at: sourceIndex), at: targetIndex)

            actions.moveHandler(folder.items[sourceIndex], targetIndex)

            let saved = try itemIDs(in: root.id, of: store)

            #expect(saved == expected, "从 \(sourceIndex) 拖到 \(targetIndex)")
        }
    }

}

// MARK: - Private

extension FolderPanelDragActionsTests {
    /// 文件夹的层级交给网格的拖动动作；轮廓的判定用不到，一律算在轮廓之内
    private func dragActions(
        for folder: Folder,
        in store: FolderStore
    ) throws -> FolderGridDragActions {
        let actions = FolderPanelController.dragActions(for: .folder(folder), in: store) { _ in
            true
        }

        return try #require(actions)
    }

    /// 按顺序列出文件夹里各项的 id
    private func itemIDs(in folderID: UUID, of store: FolderStore) throws -> [UUID] {
        try #require(store.folder(id: folderID)).items.map(\.id)
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
