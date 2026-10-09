import Foundation
import Testing

@testable import Flotilla

// MARK: - GroupPanelDragActionsTests

/// 面板只让 Flotilla 的文件夹的层级拖动：网格交出的目标格要换算成数据源的下标，保存下来的顺序才与松开前看到的相同；
/// 拖出面板删除的只是文件夹里的这一项，磁盘上的文件不动
@MainActor
final class GroupPanelDragActionsTests {
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
        let store = GroupStore(fileURL: directory.appending(path: "folders.json"))

        let finderFolder = FileReference(
            id: UUID(),
            url: URL(filePath: "/Users/Shared/", directoryHint: .isDirectory),
            bookmark: nil
        )

        let actions = GroupPanelController.dragActions(
            for: .finderFolder(finderFolder, items: []),
            in: store,
            containsScreenPoint: { _ in true },
            removeBoundaryContainsScreenPoint: { _ in true },
            releaseHandler: { }
        )

        #expect(actions == nil)
    }

    /// 向后、向前与原地：保存回调按目标格移动之后，文件夹里的顺序就是 “拖动的项放到目标格” 之后的顺序
    @Test
    func moveHandlerSavesDisplayedOrder() throws {
        let cases = [(0, 3), (1, 2), (3, 0), (2, 1), (1, 1)]

        for (sourceIndex, targetIndex) in cases {
            let fileURL = directory.appending(path: "\(UUID().uuidString).json")
            let store = GroupStore(fileURL: fileURL)
            let root = store.addRootGroup(named: "根")

            store.addItems(try webPages(count: 4), to: root.id)

            let group = try #require(store.group(id: root.id))
            let actions = try dragActions(for: group, in: store)

            var expected = group.items.map(\.id)
            expected.insert(expected.remove(at: sourceIndex), at: targetIndex)

            actions.moveHandler(group.items[sourceIndex], targetIndex)

            let saved = try itemIDs(in: root.id, of: store)

            #expect(saved == expected, "从 \(sourceIndex) 拖到 \(targetIndex)")
        }
    }

    /// 删除回调删掉的是文件夹里的这一项：子文件夹连同其中的内容一起删除，其它项不变，磁盘上的文件仍在
    @Test
    func removeHandlerRemovesOnlyThatItem() throws {
        let store = GroupStore(fileURL: directory.appending(path: "folders.json"))
        let root = store.addRootGroup(named: "根")
        let child = try #require(store.addSubgroup(named: "子", to: root.id))
        let fileURL = directory.appending(path: "说明.txt")
        let filePath = fileURL.path(percentEncoded: false)

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        try Data("说明".utf8).write(to: fileURL)

        let fileItem = try #require(GroupItem(url: fileURL, title: nil))

        store.addItems([fileItem], to: root.id)
        store.addItems(try webPages(count: 1), to: child.id)

        let group = try #require(store.group(id: root.id))
        let actions = try dragActions(for: group, in: store)
        let file = try #require(group.items.last)

        actions.removeHandler(.group(child))

        #expect(store.group(id: child.id) == nil)
        #expect(try itemIDs(in: root.id, of: store) == [file.id])

        actions.removeHandler(file)

        #expect(try itemIDs(in: root.id, of: store).isEmpty)
        #expect(FileManager.default.fileExists(atPath: filePath))
    }
}

// MARK: - Private

extension GroupPanelDragActionsTests {
    /// 文件夹的层级交给网格的拖动动作；轮廓与 “移除” 的边界的判定用不到，一律算在之内；松开时的回调也用不到
    private func dragActions(
        for group: Group,
        in store: GroupStore
    ) throws -> GroupGridDragActions {
        let actions = GroupPanelController.dragActions(
            for: .group(group),
            in: store,
            containsScreenPoint: { _ in true },
            removeBoundaryContainsScreenPoint: { _ in true },
            releaseHandler: { }
        )

        return try #require(actions)
    }

    /// 按顺序列出文件夹里各项的 id
    private func itemIDs(in groupID: UUID, of store: GroupStore) throws -> [UUID] {
        try #require(store.group(id: groupID)).items.map(\.id)
    }

    /// 网址各不相同的网页：同一文件夹里按网址去重，网址相同的不会都加进去
    private func webPages(count: Int) throws -> [GroupItem] {
        try (0 ..< count).map {
            .webPage(WebPageReference(
                id: UUID(),
                url: try #require(URL(string: "https://example.com/\($0)")),
                title: "网页\($0)"
            ))
        }
    }
}
