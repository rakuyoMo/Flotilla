import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderTreeDataSourceTests

/// 设置窗口文件夹树的拖放落点：outline view 给出的建议位置要换算成 `FolderStore.move` 能接受的目标
@MainActor
final class FolderTreeDataSourceTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例使用的数据源
    private let store: FolderStore

    /// 根文件夹“工作”
    private let work: Folder

    /// “工作”下的子文件夹“开发”
    private let development: Folder

    /// “工作”下的 App
    private let appID: UUID

    /// 被测数据源
    private let dataSource: FolderTreeDataSource

    /// 建立“工作 / [开发, Chess]”的树
    init() throws {
        store = FolderStore(fileURL: directory.appending(path: "folders.json"))

        work = store.addRootFolder(named: "工作")
        development = try #require(store.addSubfolder(named: "开发", to: work.id))

        let chess = try #require(
            FolderItem(url: URL(filePath: "/System/Applications/Chess.app"), title: nil)
        )

        store.addItems([chess], to: work.id)
        appID = try #require(store.folder(id: work.id)?.items.last?.id)

        dataSource = FolderTreeDataSource(store: store)
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 节点记住父节点，App 行所属的文件夹是它的父文件夹
    @Test
    func nodesKnowTheirContainingFolder() throws {
        let appNode = try #require(dataSource.node(withID: appID))
        let developmentNode = try #require(dataSource.node(withID: development.id))

        #expect(appNode.parent?.item.id == work.id)
        #expect(appNode.containingFolderID == work.id)
        #expect(developmentNode.containingFolderID == development.id)
    }

    /// 落在文件夹行上时追加到该文件夹末尾
    @Test
    func dropOnFolderAppendsToEnd() throws {
        let workNode = try #require(dataSource.node(withID: work.id))

        let destination = dataSource.moveDestination(
            for: appID,
            proposedParent: workNode,
            childIndex: NSOutlineViewDropOnItemIndex
        )

        #expect(destination?.folderID == work.id)
        #expect(destination?.index == 2)
    }

    /// 落在两行之间时沿用 outline view 给出的下标
    @Test
    func dropBetweenRowsKeepsProposedIndex() throws {
        let workNode = try #require(dataSource.node(withID: work.id))

        let destination = dataSource.moveDestination(
            for: appID,
            proposedParent: workNode,
            childIndex: 0
        )

        #expect(destination?.folderID == work.id)
        #expect(destination?.index == 0)
    }

    /// App 行不能作为落点
    @Test
    func rejectsDropOnApp() throws {
        let appNode = try #require(dataSource.node(withID: appID))

        let destination = dataSource.moveDestination(
            for: development.id,
            proposedParent: appNode,
            childIndex: NSOutlineViewDropOnItemIndex
        )

        #expect(destination == nil)
    }

    /// 根层级只接受文件夹
    @Test
    func rootAcceptsFoldersOnly() {
        let appDestination = dataSource.moveDestination(
            for: appID,
            proposedParent: nil,
            childIndex: 0
        )

        #expect(appDestination == nil)

        let folderDestination = dataSource.moveDestination(
            for: development.id,
            proposedParent: nil,
            childIndex: 1
        )

        #expect(folderDestination?.folderID == nil)
        #expect(folderDestination?.index == 1)
    }

    /// 文件夹不能拖进自己的子孙
    @Test
    func rejectsDropIntoDescendant() throws {
        let developmentNode = try #require(dataSource.node(withID: development.id))

        let destination = dataSource.moveDestination(
            for: work.id,
            proposedParent: developmentNode,
            childIndex: NSOutlineViewDropOnItemIndex
        )

        #expect(destination == nil)
    }
}
