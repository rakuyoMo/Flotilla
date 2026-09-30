import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderStoreItemLocationTests

/// App 与文件移动或改名后，这一项按书签跟到新位置：点击时才能打开，tile 图标才画得出它；
/// 位置没变时不能提交，否则每次展开面板、每次设置窗口来到前台都会让 Dock 同步一遍
@MainActor
final class FolderStoreItemLocationTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例使用的数据源
    private let store: FolderStore

    /// 根文件夹“工作”
    private let work: Folder

    /// 建好临时目录与只有一个根文件夹“工作”的数据源
    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        store = FolderStore(fileURL: directory.appending(path: "folders.json"))
        work = store.addRootFolder(named: "工作")
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: 跟随

    /// 文件改名后换成新路径，id 不变，只发一次变更通知
    @Test
    func renamedFileFollows() async throws {
        let original = try addFile(named: "报告.txt")

        try move("报告.txt", to: "年度报告.txt")

        try await expectNotifications(1) {
            store.updateItemLocations()
        }

        let file = try onlyFile(in: work.id)

        #expect(file.id == original.id)
        #expect(file.url == fileURL(of: "年度报告.txt"))
    }

    /// 文件移到别的目录后换成新路径，id 不变，只发一次变更通知
    @Test
    func movedFileFollows() async throws {
        let original = try addFile(named: "报告.txt")

        try createDirectory("归档")
        try move("报告.txt", to: "归档/报告.txt")

        try await expectNotifications(1) {
            store.updateItemLocations()
        }

        let file = try onlyFile(in: work.id)

        #expect(file.id == original.id)
        #expect(file.url == fileURL(of: "归档/报告.txt"))
    }

    /// 访达里的文件夹改名后同样跟上，仍按目录 URL 记录
    @Test
    func renamedFinderFolderFollows() async throws {
        try createDirectory("资料")

        let original = try add(directory.appending(path: "资料"))

        try move("资料", to: "旧资料")

        try await expectNotifications(1) {
            store.updateItemLocations()
        }

        let file = try onlyFile(in: work.id)

        #expect(file.id == original.id)
        #expect(file.url == directoryURL(of: "旧资料"))
    }

    /// 只更新指定文件夹及其子孙，其它根文件夹里改了名的文件保持原样
    @Test
    func updatesOnlyGivenFolderSubtree() throws {
        let archive = try #require(store.addSubfolder(named: "归档", to: work.id))
        let personal = store.addRootFolder(named: "个人")

        _ = try addFile(named: "报告.txt", to: archive.id)
        let inPersonal = try addFile(named: "照片.txt", to: personal.id)

        try move("报告.txt", to: "年度报告.txt")
        try move("照片.txt", to: "旧照片.txt")

        store.updateItemLocations(in: work.id)

        #expect(try onlyFile(in: archive.id).url == fileURL(of: "年度报告.txt"))
        #expect(try onlyFile(in: personal.id).url == inPersonal.url)
    }

    // MARK: 不变

    /// 什么都没变时不提交、不发通知
    @Test
    func unchangedFilesDoNotNotify() async throws {
        _ = try addFile(named: "报告.txt")
        let before = store.rootFolders

        try await expectNotifications(0) {
            store.updateItemLocations()
        }

        #expect(store.rootFolders == before)
    }

    /// 临时目录的 `/var` 与 `/private/var` 是符号链接的两种写法，书签解析出的写法与记录的不同也不算移动
    @Test
    func symlinkSpellingIsNotMove() async throws {
        let original = try addFile(named: "报告.txt")
        let canonicalPath = try realPath(of: original.url)

        // 把记录的路径换成解析过符号链接的写法，书签不变
        let respelled = FileReference(
            id: UUID(),
            url: URL(filePath: canonicalPath),
            bookmark: original.bookmark
        )

        let personal = store.addRootFolder(named: "个人")
        store.addItems([.file(respelled)], to: personal.id)

        let before = store.rootFolders

        try await expectNotifications(0) {
            store.updateItemLocations()
        }

        #expect(store.rootFolders == before)
    }

    /// 文件已删除时书签解析失败，这一项保持原样，也不发通知
    @Test
    func deletedFileStaysUnchanged() async throws {
        _ = try addFile(named: "报告.txt")
        try FileManager.default.removeItem(at: directory.appending(path: "报告.txt"))

        let before = store.rootFolders

        try await expectNotifications(0) {
            store.updateItemLocations()
        }

        #expect(store.rootFolders == before)
    }

    /// 没有书签的项在文件还在原路径时补建书签，路径不变
    @Test
    func fileWithoutBookmarkGainsBookmark() async throws {
        try Data("报告".utf8).write(to: directory.appending(path: "报告.txt"))

        let legacy = FileReference(id: UUID(), url: fileURL(of: "报告.txt"), bookmark: nil)
        store.addItems([.file(legacy)], to: work.id)

        try await expectNotifications(1) {
            store.updateItemLocations()
        }

        let file = try onlyFile(in: work.id)

        #expect(file.id == legacy.id)
        #expect(file.url == legacy.url)
        #expect(file.bookmark != nil)
    }

    // MARK: App

    /// App 改名后换成新路径，id 不变，只发一次变更通知
    @Test
    func renamedAppFollows() async throws {
        let original = try addApp(named: "Tool.app")

        try move("Tool.app", to: "Tool 2.app")

        try await expectNotifications(1) {
            store.updateItemLocations()
        }

        let app = try onlyApp(in: work.id)

        #expect(app.id == original.id)
        #expect(app.url == directoryURL(of: "Tool 2.app"))
    }

    /// App 移到别的目录后换成新路径，id 不变，只发一次变更通知
    @Test
    func movedAppFollows() async throws {
        let original = try addApp(named: "Tool.app")

        try createDirectory("应用程序")
        try move("Tool.app", to: "应用程序/Tool.app")

        try await expectNotifications(1) {
            store.updateItemLocations()
        }

        let app = try onlyApp(in: work.id)

        #expect(app.id == original.id)
        #expect(app.url == directoryURL(of: "应用程序/Tool.app"))
    }

    /// App 被原地换成新版本、旧版本移到别处：书签解析按路径优先，留在原路径并重建书签；
    /// 之后再移动新版本，跟着新版本走，而不是跟到被换走的旧版本
    @Test
    func replacedAppFollowsNewVersion() async throws {
        let original = try addApp(named: "Tool.app")

        try createDirectory("废纸篓")
        try move("Tool.app", to: "废纸篓/Tool.app")
        try createDirectory("Tool.app")

        try await expectNotifications(1) {
            store.updateItemLocations()
        }

        let replaced = try onlyApp(in: work.id)

        #expect(replaced.url == original.url)
        #expect(replaced.bookmark != original.bookmark)

        try move("Tool.app", to: "Tool 2.app")

        store.updateItemLocations()

        #expect(try onlyApp(in: work.id).url == directoryURL(of: "Tool 2.app"))
    }

    /// 没有书签的 App 项在 App 还在原路径时补建书签，路径不变
    @Test
    func appWithoutBookmarkGainsBookmark() async throws {
        try createDirectory("Tool.app")

        let legacy = AppReference(id: UUID(), url: directoryURL(of: "Tool.app"), bookmark: nil)
        store.addItems([.app(legacy)], to: work.id)

        try await expectNotifications(1) {
            store.updateItemLocations()
        }

        let app = try onlyApp(in: work.id)

        #expect(app.id == legacy.id)
        #expect(app.url == legacy.url)
        #expect(app.bookmark != nil)
    }

    /// 没有书签的 App 项在 App 已删除时保持原样，也不发通知
    @Test
    func deletedAppWithoutBookmarkStaysUnchanged() async throws {
        let legacy = AppReference(id: UUID(), url: directoryURL(of: "Tool.app"), bookmark: nil)
        store.addItems([.app(legacy)], to: work.id)

        let before = store.rootFolders

        try await expectNotifications(0) {
            store.updateItemLocations()
        }

        #expect(store.rootFolders == before)
    }

    // MARK: 加入

    /// 文件改名后把新路径加入同一个文件夹：已有的那一项跟到新路径，不重复加入，只发一次变更通知
    @Test
    func addingRenamedFileDoesNotDuplicate() async throws {
        let original = try addFile(named: "报告.txt")

        try move("报告.txt", to: "年度报告.txt")

        let renamed = try #require(
            FolderItem(url: directory.appending(path: "年度报告.txt"), title: nil)
        )

        try await expectNotifications(1) {
            store.addItems([renamed], to: work.id)
        }

        let file = try onlyFile(in: work.id)

        #expect(file.id == original.id)
        #expect(file.url == fileURL(of: "年度报告.txt"))
    }

    /// App 改名后把新路径加入同一个文件夹：已有的那一项跟到新路径，不重复加入，只发一次变更通知
    @Test
    func addingRenamedAppDoesNotDuplicate() async throws {
        let original = try addApp(named: "Tool.app")

        try move("Tool.app", to: "Tool 2.app")

        let renamed = try #require(
            FolderItem(url: directory.appending(path: "Tool 2.app"), title: nil)
        )

        try await expectNotifications(1) {
            store.addItems([renamed], to: work.id)
        }

        let app = try onlyApp(in: work.id)

        #expect(app.id == original.id)
        #expect(app.url == directoryURL(of: "Tool 2.app"))
    }
}

// MARK: - Private

extension FolderStoreItemLocationTests {
    /// 项是 App 时返回它的引用
    private static func appReference(of item: FolderItem) -> AppReference? {
        guard case .app(let app) = item else { return nil }

        return app
    }

    /// 项是文件时返回它的引用
    private static func fileReference(of item: FolderItem) -> FileReference? {
        guard case .file(let file) = item else { return nil }

        return file
    }

    /// 在临时目录里新建文件，经分类后加入文件夹，返回加入的文件项
    /// - Parameters:
    ///   - name: 文件名
    ///   - folderID: 目标文件夹，默认是“工作”
    private func addFile(named name: String, to folderID: UUID? = nil) throws -> FileReference {
        try Data(name.utf8).write(to: directory.appending(path: name))

        return try add(directory.appending(path: name), to: folderID)
    }

    /// 把本地 URL 经分类后加入文件夹，返回加入的文件项
    private func add(_ url: URL, to folderID: UUID? = nil) throws -> FileReference {
        let item = try #require(FolderItem(url: url, title: nil))
        let file = try #require(Self.fileReference(of: item), "应当是文件")

        store.addItems([item], to: folderID ?? work.id)

        return file
    }

    /// 在临时目录里新建一个 `.app` 目录，经分类后作为 App 加入“工作”，返回加入的 App 项
    private func addApp(named name: String) throws -> AppReference {
        try createDirectory(name)

        let item = try #require(FolderItem(url: directory.appending(path: name), title: nil))
        let app = try #require(Self.appReference(of: item), "应当是 App")

        store.addItems([item], to: work.id)

        return app
    }

    /// 在临时目录里新建目录
    private func createDirectory(_ name: String) throws {
        try FileManager.default.createDirectory(
            at: directory.appending(path: name),
            withIntermediateDirectories: true
        )
    }

    /// 在临时目录里移动或改名
    private func move(_ source: String, to destination: String) throws {
        try FileManager.default.moveItem(
            at: directory.appending(path: source),
            to: directory.appending(path: destination)
        )
    }

    /// 文件夹里唯一的一项，它必须是文件
    private func onlyFile(in folderID: UUID) throws -> FileReference {
        let items = try #require(store.folder(id: folderID)).items

        try #require(items.count == 1, "文件夹里应当只有一项：\(items)")

        return try #require(Self.fileReference(of: items[0]), "应当是文件")
    }

    /// 文件夹里唯一的一项，它必须是 App
    private func onlyApp(in folderID: UUID) throws -> AppReference {
        let items = try #require(store.folder(id: folderID)).items

        try #require(items.count == 1, "文件夹里应当只有一项：\(items)")

        return try #require(Self.appReference(of: items[0]), "应当是 App")
    }

    /// 执行 body，期间 `FolderStore` 恰好发出 expectedCount 次变更通知
    private func expectNotifications(
        _ expectedCount: Int,
        during body: () throws -> Void
    ) async throws {
        try await confirmation(expectedCount: expectedCount) { changed in
            let observer = NotificationCenter.default.addObserver(
                forName: FolderStore.didChangeNotification,
                object: store,
                queue: nil
            ) { _ in
                changed()
            }

            defer { NotificationCenter.default.removeObserver(observer) }

            try body()
        }
    }

    /// 临时目录里某一项的 POSIX 路径
    private func path(of name: String) -> String {
        directory.appending(path: name).path(percentEncoded: false)
    }

    /// 临时目录里某个目录的目录 URL，与分类后记录的写法一致
    private func directoryURL(of name: String) -> URL {
        URL(filePath: path(of: name), directoryHint: .isDirectory)
    }

    /// 临时目录里某个文件的文件 URL，与分类后记录的写法一致
    private func fileURL(of name: String) -> URL {
        URL(filePath: path(of: name), directoryHint: .notDirectory)
    }

    /// 解析全部符号链接之后的真实路径，例如把 `/var` 解析成 `/private/var`
    private func realPath(of url: URL) throws -> String {
        let resolved = try #require(realpath(url.path(percentEncoded: false), nil))
        defer { free(resolved) }

        return String(cString: resolved)
    }
}
