import AppKit
import Testing

@testable import Flotilla

// MARK: - GroupTreeDataSourceTests

/// 设置窗口组树的拖放：outline view 给出的建议位置要换算成 `GroupStore.move` 能接受的目标；
/// 从访达、浏览器拖入的东西只有能加入组的才被接收
@MainActor
final class GroupTreeDataSourceTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例使用的 `GroupStore`
    private let store: GroupStore

    /// 根组 “工作”
    private let work: Group

    /// “工作” 下的子组 “开发”
    private let development: Group

    /// “工作” 下 App 项的 id
    private let appID: UUID

    /// 被测数据源
    private let dataSource: GroupTreeDataSource

    /// 建立根组 “工作”，其下依次是子组 “开发” 与 Chess.app
    init() throws {
        store = GroupStore(fileURL: directory.appending(path: "folders.json"))

        work = store.addRootGroup(named: "工作")
        development = try #require(store.addSubgroup(named: "开发", to: work.id))

        let chess = try #require(
            GroupItem(url: URL(filePath: "/System/Applications/Chess.app"), title: nil)
        )

        store.addItems([chess], to: work.id)
        appID = try #require(store.group(id: work.id)?.items.last?.id)

        dataSource = GroupTreeDataSource(store: store)
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 节点记住父节点，App 行所属的组是它的父组
    @Test
    func nodesKnowTheirContainingGroup() throws {
        let appNode = try #require(dataSource.node(withID: appID))
        let developmentNode = try #require(dataSource.node(withID: development.id))

        #expect(appNode.parent?.item.id == work.id)
        #expect(appNode.containingGroupID == work.id)
        #expect(developmentNode.containingGroupID == development.id)
    }

    /// 落在组的行上时追加到该组末尾
    @Test
    func dropOnGroupAppendsToEnd() throws {
        let workNode = try #require(dataSource.node(withID: work.id))

        let destination = dataSource.moveDestination(
            for: appID,
            proposedParent: workNode,
            childIndex: NSOutlineViewDropOnItemIndex
        )

        #expect(destination?.groupID == work.id)
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

        #expect(destination?.groupID == work.id)
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

    /// 根层级只接受组
    @Test
    func rootAcceptsGroupsOnly() {
        let appDestination = dataSource.moveDestination(
            for: appID,
            proposedParent: nil,
            childIndex: 0
        )

        #expect(appDestination == nil)

        let groupDestination = dataSource.moveDestination(
            for: development.id,
            proposedParent: nil,
            childIndex: 1
        )

        #expect(groupDestination?.groupID == nil)
        #expect(groupDestination?.index == 1)
    }

    /// 组不能拖进自己的子孙
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

    /// 浏览器拖出的网址落在组的行上，加入带标题的网页
    @Test
    func dropsWebPageWithTitleOntoGroup() throws {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("https://example.com/", forType: .URL)
        pasteboardItem.setString(
            " Example Domain ",
            forType: GroupTreeDataSource.urlNamePasteboardType
        )

        let result = try drop([pasteboardItem], onto: work.id)

        #expect(result.operation == .copy)
        #expect(result.accepted)

        guard case .webPage(let webPage) = try #require(store.group(id: work.id)).items.last else {
            Issue.record("组末尾应当是网页")
            return
        }

        #expect(webPage.url.absoluteString == "https://example.com/")
        #expect(webPage.title == "Example Domain")
    }

    /// 访达拖出的文件落在组的行上，加入文件
    @Test
    func dropsFileOntoGroup() throws {
        let fileURL = directory.appending(path: "报告.txt")
        try Data("报告".utf8).write(to: fileURL)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)

        let result = try drop([pasteboardItem], onto: work.id)

        #expect(result.operation == .copy)
        #expect(result.accepted)

        guard case .file(let file) = try #require(store.group(id: work.id)).items.last else {
            Issue.record("组末尾应当是文件")
            return
        }

        #expect(file.url.path(percentEncoded: false) == fileURL.path(percentEncoded: false))
    }

    /// 访达文件夹落在组的行上，作为文件加入，按目录 URL 记录
    @Test
    func dropsFinderFolderOntoGroup() throws {
        let folderURL = directory.appending(path: "资料", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(folderURL.absoluteString, forType: .fileURL)

        let result = try drop([pasteboardItem], onto: work.id)

        #expect(result.operation == .copy)
        #expect(result.accepted)

        guard case .file(let file) = try #require(store.group(id: work.id)).items.last else {
            Issue.record("组末尾应当是访达文件夹")
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

        let before = store.rootGroups
        let result = try drop([missingFile, ftpAddress], onto: work.id)

        #expect(result.operation.isEmpty)
        #expect(!result.accepted)
        #expect(store.rootGroups == before)
    }

    /// 文件行与网页行不能作为落点：它们不能包含其它项
    @Test
    func rejectsDropOnFileOrWebPageRow() throws {
        let report = GroupItem.file(
            FileReference(id: UUID(), url: URL(filePath: "/etc/hosts"), bookmark: nil)
        )
        let exampleURL = try #require(URL(string: "https://example.com/"))
        let example = GroupItem.webPage(WebPageReference(id: UUID(), url: exampleURL, title: nil))

        store.addItems([report, example], to: work.id)
        dataSource.reloadNodes()

        let before = store.rootGroups

        for rowID in [report.id, example.id] {
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString("https://example.org/", forType: .URL)

            let result = try drop([pasteboardItem], onto: rowID)

            #expect(result.operation.isEmpty)
            #expect(!result.accepted)
        }

        #expect(store.rootGroups == before)
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

        // 校验时数据源会把落点改到组的行上，需要一个显示这棵树的 outline view
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
