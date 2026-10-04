import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderTreeDataSourceTests

/// 设置窗口文件夹树的拖放：outline view 给出的建议位置要换算成 `FolderStore.move` 能接受的目标；
/// 从访达、浏览器拖入的东西只有能加入文件夹的才被接收
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

    /// “工作”下 App 项的 id
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

    // MARK: 从外部拖入

    /// 浏览器拖出的网址落在文件夹行上，加入带标题的网页
    @Test
    func dropsWebPageWithTitleOntoFolder() throws {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("https://example.com/", forType: .URL)
        pasteboardItem.setString(
            " Example Domain ",
            forType: FolderTreeDataSource.urlNamePasteboardType
        )

        let result = try drop([pasteboardItem], onto: work.id)

        #expect(result.operation == .copy)
        #expect(result.accepted)

        guard case .webPage(let webPage) = try #require(store.folder(id: work.id)).items.last else {
            Issue.record("文件夹末尾应当是网页")
            return
        }

        #expect(webPage.url.absoluteString == "https://example.com/")
        #expect(webPage.title == "Example Domain")
    }

    /// 访达拖出的文件落在文件夹行上，加入文件
    @Test
    func dropsFileOntoFolder() throws {
        let fileURL = directory.appending(path: "报告.txt")
        try Data("报告".utf8).write(to: fileURL)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)

        let result = try drop([pasteboardItem], onto: work.id)

        #expect(result.operation == .copy)
        #expect(result.accepted)

        guard case .file(let file) = try #require(store.folder(id: work.id)).items.last else {
            Issue.record("文件夹末尾应当是文件")
            return
        }

        #expect(file.url.path(percentEncoded: false) == fileURL.path(percentEncoded: false))
    }

    /// 访达里的文件夹落在文件夹行上，作为文件加入，按目录 URL 记录
    @Test
    func dropsFinderFolderOntoFolder() throws {
        let folderURL = directory.appending(path: "资料", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(folderURL.absoluteString, forType: .fileURL)

        let result = try drop([pasteboardItem], onto: work.id)

        #expect(result.operation == .copy)
        #expect(result.accepted)

        guard case .file(let file) = try #require(store.folder(id: work.id)).items.last else {
            Issue.record("文件夹末尾应当是访达里的文件夹")
            return
        }

        #expect(file.url.hasDirectoryPath)
        #expect(file.url.path(percentEncoded: false) == folderURL.path(percentEncoded: false))
    }

    /// 一个能加入的项都没有时不接收：已不存在的文件、`http`、`https` 以外的网址
    @Test
    func rejectsItemsThatCannotBeAdded() throws {
        let missingFile = NSPasteboardItem()
        missingFile.setString(
            directory.appending(path: "不存在的文件.txt").absoluteString,
            forType: .fileURL
        )

        let ftpAddress = NSPasteboardItem()
        ftpAddress.setString("ftp://example.com/file.txt", forType: .URL)

        let before = store.rootFolders
        let result = try drop([missingFile, ftpAddress], onto: work.id)

        #expect(result.operation.isEmpty)
        #expect(!result.accepted)
        #expect(store.rootFolders == before)
    }

    /// 文件行与网页行不能作为落点：它们不能包含其它项
    @Test
    func rejectsDropOnFileOrWebPageRow() throws {
        let report = FolderItem.file(
            FileReference(id: UUID(), url: URL(filePath: "/etc/hosts"), bookmark: nil)
        )
        let exampleURL = try #require(URL(string: "https://example.com/"))
        let example = FolderItem.webPage(WebPageReference(id: UUID(), url: exampleURL, title: nil))

        store.addItems([report, example], to: work.id)
        dataSource.reloadNodes()

        let before = store.rootFolders

        for rowID in [report.id, example.id] {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString("https://example.org/", forType: .URL)

            let result = try drop([pasteboardItem], onto: rowID)

            #expect(result.operation.isEmpty)
            #expect(!result.accepted)
        }

        #expect(store.rootFolders == before)
    }

    /// 把剪贴板项从外部拖到某一行上，分别走一遍校验与放下
    /// - Returns: 校验给出的拖放操作，以及放下是否被接收
    private func drop(
        _ pasteboardItems: [NSPasteboardItem],
        onto itemID: UUID
    ) throws -> (operation: NSDragOperation, accepted: Bool) {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.writeObjects(pasteboardItems)

        let info = DraggingInfoStub(pasteboard: pasteboard)
        let node = try #require(dataSource.node(withID: itemID))

        // 校验时数据源会把落点改到文件夹行上，需要一个显示这棵树的 outline view
        let outlineView = NSOutlineView()
        outlineView.dataSource = dataSource
        outlineView.reloadData()

        let operation = dataSource.outlineView(
            outlineView,
            validateDrop: info,
            proposedItem: node,
            proposedChildIndex: NSOutlineViewDropOnItemIndex
        )

        let accepted = dataSource.outlineView(
            outlineView,
            acceptDrop: info,
            item: node,
            childIndex: NSOutlineViewDropOnItemIndex
        )

        return (operation, accepted)
    }
}
