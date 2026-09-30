import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderStoreFileLocationTests

/// 文件移动或改名后，文件项按书签跟到新位置：点击时才能打开，tile 图标才画得出它；
/// 位置没变时不能提交，否则每次展开面板、每次设置窗口来到前台都会让 Dock 同步一遍
@MainActor
final class FolderStoreFileLocationTests {
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
            store.updateFileLocations()
        }

        let file = try onlyFile(in: work.id)

        #expect(file.id == original.id)
        #expect(file.url == fileURL(of: "年度报告.txt"))
    }

    /// 文件移到别的目录后换成新路径，id 不变，只发一次变更通知
    @Test
    func movedFileFollows() async throws {
        let original = try addFile(named: "报告.txt")

        try FileManager.default.createDirectory(
            at: directory.appending(path: "归档"),
            withIntermediateDirectories: true
        )

        try move("报告.txt", to: "归档/报告.txt")

        try await expectNotifications(1) {
            store.updateFileLocations()
        }

        let file = try onlyFile(in: work.id)

        #expect(file.id == original.id)
        #expect(file.url == fileURL(of: "归档/报告.txt"))
    }

    /// 访达里的文件夹改名后同样跟上，仍按目录 URL 记录
    @Test
    func renamedFinderFolderFollows() async throws {
        try FileManager.default.createDirectory(
            at: directory.appending(path: "资料"),
            withIntermediateDirectories: true
        )

        let original = try add(directory.appending(path: "资料"))

        try move("资料", to: "旧资料")

        try await expectNotifications(1) {
            store.updateFileLocations()
        }

        let file = try onlyFile(in: work.id)
        let expectedURL = URL(filePath: path(of: "旧资料"), directoryHint: .isDirectory)

        #expect(file.id == original.id)
        #expect(file.url == expectedURL)
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

        store.updateFileLocations(in: work.id)

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
            store.updateFileLocations()
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
            store.updateFileLocations()
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
            store.updateFileLocations()
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
            store.updateFileLocations()
        }

        let file = try onlyFile(in: work.id)

        #expect(file.id == legacy.id)
        #expect(file.url == legacy.url)
        #expect(file.bookmark != nil)
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
}

// MARK: - Private

extension FolderStoreFileLocationTests {
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
