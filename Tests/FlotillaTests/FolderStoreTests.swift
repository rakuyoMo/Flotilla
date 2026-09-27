import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderStoreTests

/// `FolderStore` 是文件夹树的唯一数据源：增删改查、移动规则与持久化都必须可靠
@MainActor
final class FolderStoreTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例使用的持久化文件
    private var fileURL: URL {
        directory.appending(path: "folders.json")
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: 增删改查

    /// 新建的根文件夹与子文件夹都能按 id 查到，子文件夹的父文件夹正确
    @Test
    func addsNestedFolders() throws {
        let store = FolderStore(fileURL: fileURL)

        let root = store.addRootFolder(named: "根")
        let child = try #require(store.addSubfolder(named: "子", to: root.id))
        let grandchild = try #require(store.addSubfolder(named: "孙", to: child.id))

        #expect(store.rootFolders.map(\.id) == [root.id])
        #expect(store.folder(id: grandchild.id)?.name == "孙")
        #expect(store.parentFolder(of: grandchild.id)?.id == child.id)
        #expect(store.parentFolder(of: child.id)?.id == root.id)
        #expect(store.parentFolder(of: root.id) == nil)
    }

    /// 父文件夹不存在时不新建子文件夹
    @Test
    func addSubfolderRequiresExistingParent() {
        let store = FolderStore(fileURL: fileURL)

        #expect(store.addSubfolder(named: "孤儿", to: UUID()) == nil)
        #expect(store.rootFolders.isEmpty)
    }

    /// 同一文件夹内相同 URL 的 App 只保留一份，其它文件夹不受影响
    @Test
    func addAppsSkipsDuplicatesWithinFolder() throws {
        let store = FolderStore(fileURL: fileURL)
        let first = store.addRootFolder(named: "一")
        let second = store.addRootFolder(named: "二")

        store.addApps([chess, calendar, chess], to: first.id)
        store.addApps([chess], to: first.id)
        store.addApps([chess], to: second.id)

        #expect(try appURLs(in: first.id, of: store) == [chess, calendar])
        #expect(try appURLs(in: second.id, of: store) == [chess])
    }

    /// 同一个 App 的不同 URL 写法（结尾斜杠、`..`）视为同一个 App
    @Test
    func addAppsNormalizesURLSpelling() throws {
        let store = FolderStore(fileURL: fileURL)
        let root = store.addRootFolder(named: "根")

        store.addApps(
            [
                URL(filePath: "/System/Applications/Chess.app"),
                URL(filePath: "/System/Applications/Utilities/../Chess.app/"),
            ],
            to: root.id
        )

        #expect(try appURLs(in: root.id, of: store) == [chess])
    }

    /// 重命名任意层级的文件夹
    @Test
    func renamesNestedFolder() throws {
        let store = FolderStore(fileURL: fileURL)
        let root = store.addRootFolder(named: "根")
        let child = try #require(store.addSubfolder(named: "旧名", to: root.id))

        store.rename(folderID: child.id, to: "新名")

        #expect(store.folder(id: child.id)?.name == "新名")
    }

    /// 删除文件夹时连同其中的 App 与子文件夹一起删除
    @Test
    func removesFolderWithContents() throws {
        let store = FolderStore(fileURL: fileURL)
        let root = store.addRootFolder(named: "根")
        let child = try #require(store.addSubfolder(named: "子", to: root.id))
        let grandchild = try #require(store.addSubfolder(named: "孙", to: child.id))

        store.addApps([chess], to: grandchild.id)

        store.remove(itemID: child.id)

        #expect(store.folder(id: child.id) == nil)
        #expect(store.folder(id: grandchild.id) == nil)
        #expect(try #require(store.folder(id: root.id)).items.isEmpty)
    }

    /// 删除文件夹中的单个 App
    @Test
    func removesApp() throws {
        let store = FolderStore(fileURL: fileURL)
        let root = store.addRootFolder(named: "根")

        store.addApps([chess, calendar], to: root.id)
        let chessID = try #require(store.folder(id: root.id)?.items.first?.id)

        store.remove(itemID: chessID)

        #expect(try appURLs(in: root.id, of: store) == [calendar])
    }

    // MARK: 移动

    /// 同一层级内向后移动：目标下标按移动前计算，移除自身后仍落在预期位置
    @Test
    func movesForwardWithinSameFolder() throws {
        let store = FolderStore(fileURL: fileURL)
        let root = store.addRootFolder(named: "根")

        store.addApps([chess, calendar, calculator], to: root.id)
        let chessID = try #require(store.folder(id: root.id)?.items.first?.id)

        store.move(itemID: chessID, to: root.id, at: 3)

        #expect(try appURLs(in: root.id, of: store) == [calendar, calculator, chess])
    }

    /// 同一层级内向前移动
    @Test
    func movesBackwardWithinSameFolder() throws {
        let store = FolderStore(fileURL: fileURL)
        let root = store.addRootFolder(named: "根")

        store.addApps([chess, calendar, calculator], to: root.id)
        let calculatorID = try #require(store.folder(id: root.id)?.items.last?.id)

        store.move(itemID: calculatorID, to: root.id, at: 0)

        #expect(try appURLs(in: root.id, of: store) == [calculator, chess, calendar])
    }

    /// App 可以移到其它文件夹
    @Test
    func movesAppAcrossFolders() throws {
        let store = FolderStore(fileURL: fileURL)
        let source = store.addRootFolder(named: "源")
        let target = store.addRootFolder(named: "目标")

        store.addApps([chess], to: source.id)
        store.addApps([calendar], to: target.id)
        let chessID = try #require(store.folder(id: source.id)?.items.first?.id)

        store.move(itemID: chessID, to: target.id, at: 0)

        #expect(try appURLs(in: source.id, of: store).isEmpty)
        #expect(try appURLs(in: target.id, of: store) == [chess, calendar])
    }

    /// 子文件夹可以移到根层级，成为新的根文件夹
    @Test
    func movesSubfolderToRoot() throws {
        let store = FolderStore(fileURL: fileURL)
        let root = store.addRootFolder(named: "根")
        let child = try #require(store.addSubfolder(named: "子", to: root.id))

        store.move(itemID: child.id, to: nil, at: 0)

        #expect(store.rootFolders.map(\.id) == [child.id, root.id])
        #expect(store.parentFolder(of: child.id) == nil)
    }

    /// App 不能放在根层级
    @Test
    func rejectsAppAtRoot() throws {
        let store = FolderStore(fileURL: fileURL)
        let root = store.addRootFolder(named: "根")

        store.addApps([chess], to: root.id)
        let chessID = try #require(store.folder(id: root.id)?.items.first?.id)

        #expect(!store.canMove(itemID: chessID, to: nil))

        store.move(itemID: chessID, to: nil, at: 0)

        #expect(store.rootFolders.map(\.id) == [root.id])
        #expect(try appURLs(in: root.id, of: store) == [chess])
    }

    /// 文件夹不能移入自身或自己的子孙，否则整棵子树会从数据中消失
    @Test
    func rejectsMovingFolderIntoItselfOrDescendant() throws {
        let store = FolderStore(fileURL: fileURL)
        let root = store.addRootFolder(named: "根")
        let child = try #require(store.addSubfolder(named: "子", to: root.id))
        let grandchild = try #require(store.addSubfolder(named: "孙", to: child.id))

        let before = store.rootFolders

        #expect(!store.canMove(itemID: root.id, to: root.id))
        #expect(!store.canMove(itemID: root.id, to: grandchild.id))
        #expect(!store.canMove(itemID: child.id, to: grandchild.id))

        store.move(itemID: root.id, to: grandchild.id, at: 0)
        store.move(itemID: child.id, to: child.id, at: 0)

        #expect(store.rootFolders == before)
    }

    // MARK: 持久化

    /// 写入临时目录后重新加载，得到完全相同的树
    @Test
    func reloadsPersistedTree() throws {
        let store = FolderStore(fileURL: fileURL)
        let root = store.addRootFolder(named: "根")
        let child = try #require(store.addSubfolder(named: "子", to: root.id))

        store.addApps([chess], to: child.id)
        store.addApps([calendar], to: root.id)

        let reloaded = FolderStore(fileURL: fileURL)

        #expect(reloaded.rootFolders == store.rootFolders)
    }

    /// 持久化文件不存在时从空开始
    @Test
    func startsEmptyWithoutFile() {
        #expect(FolderStore(fileURL: fileURL).rootFolders.isEmpty)
    }

    /// 文件损坏时改名保留原文件并从空开始，用户数据不会被下一次写入覆盖
    @Test
    func preservesBrokenFile() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let brokenContent = Data("{ 这不是 JSON".utf8)
        try brokenContent.write(to: fileURL)

        let store = FolderStore(fileURL: fileURL)

        let files = try FileManager.default.contentsOfDirectory(
            atPath: directory.path(percentEncoded: false)
        )

        let brokenFile = try #require(files.first { $0.hasPrefix("folders.json.broken-") })

        #expect(store.rootFolders.isEmpty)
        #expect(!files.contains("folders.json"))
        #expect(try Data(contentsOf: directory.appending(path: brokenFile)) == brokenContent)
    }

    /// 每次变更都发出通知，没有改动时不发
    @Test
    func notifiesOnEveryChange() async throws {
        let store = FolderStore(fileURL: fileURL)

        try await confirmation(expectedCount: 3) { changed in
            let observer = NotificationCenter.default.addObserver(
                forName: FolderStore.didChangeNotification,
                object: store,
                queue: nil
            ) { _ in
                changed()
            }

            defer { NotificationCenter.default.removeObserver(observer) }

            let root = store.addRootFolder(named: "根")
            store.rename(folderID: root.id, to: "根")
            store.rename(folderID: root.id, to: "新根")
            store.addApps([], to: root.id)
            store.remove(itemID: UUID())
            _ = try #require(store.addSubfolder(named: "子", to: root.id))
        }
    }
}

// MARK: - Fixtures

extension FolderStoreTests {
    /// 测试用的 App URL
    private var chess: URL {
        URL(filePath: "/System/Applications/Chess.app/")
    }

    /// 测试用的 App URL
    private var calendar: URL {
        URL(filePath: "/System/Applications/Calendar.app/")
    }

    /// 测试用的 App URL
    private var calculator: URL {
        URL(filePath: "/System/Applications/Calculator.app/")
    }

    /// 按顺序列出文件夹里 App 的 URL
    private func appURLs(in folderID: UUID, of store: FolderStore) throws -> [URL] {
        let folder = try #require(store.folder(id: folderID))

        return folder.items.compactMap {
            guard case .app(let app) = $0 else { return nil }
            return app.url
        }
    }
}
