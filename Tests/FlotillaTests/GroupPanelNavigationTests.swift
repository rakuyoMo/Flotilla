import Foundation
import Testing

@testable import Flotilla

// MARK: - GroupPanelNavigationTests

/// 导航路径的解析：展示期间组树变化时，当前层级还在就保留，当前层级不在该根组之下、或读不出来就收起；
/// 访达文件夹的层级每次解析都重新读目录，返回时父层级才与磁盘一致
@MainActor
final class GroupPanelNavigationTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 根组 “根” 的 id：每条导航路径的第一段
    private let rootID = UUID()

    /// 子组 “子” 的 id：每次取 `child` 都按它重建，内容变了仍是同一层级
    private let childID = UUID()

    /// 最深一层的子组
    private let grandchild = Group(id: UUID(), name: "孙", items: [])

    /// 根组里与子组并列的 App 项
    private let app = GroupItem.app(AppReference(
        id: UUID(),
        url: URL(filePath: "/System/Applications/Chess.app"),
        bookmark: nil,
        bundleIdentifier: nil
    ))

    /// 本用例里读访达文件夹用的内容，模拟一次展开
    private var finderFolderContents = FinderFolderContents()

    /// 根组下的子组
    private var child: Group {
        Group(id: childID, name: "子", items: [.group(grandchild)])
    }

    /// 根 → 子 → 孙
    private var root: Group {
        Group(id: rootID, name: "根", items: [app, .group(child)])
    }

    /// 建好临时目录：访达文件夹 “资料”，其中有子目录 “2024” 与文件 “说明.txt”，“2024” 里有 “报告.txt”
    init() throws {
        try FileManager.default.createDirectory(
            at: directory.appending(path: "资料/2024"),
            withIntermediateDirectories: true
        )

        try Data("说明".utf8).write(to: directory.appending(path: "资料/说明.txt"))
        try Data("报告".utf8).write(to: directory.appending(path: "资料/2024/报告.txt"))
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: 组

    /// 沿路径逐层找到当前层级
    @Test
    func resolvesEachLevelAlongPath() {
        let rootGroups = [root]
        let grandchildPath = [rootID, childID, grandchild.id]

        #expect(resolve([rootID], in: rootGroups) == .group(root))
        #expect(resolve([rootID, childID], in: rootGroups) == .group(child))
        #expect(resolve(grandchildPath, in: rootGroups) == .group(grandchild))
    }

    /// 当前层级的内容变化后，解析出的是变化后的组，层级保持不变
    @Test
    func keepsLevelWhenContentChanges() {
        var renamedChild = child
        renamedChild.name = "改名后的子"
        renamedChild.items.append(app)

        let changedRoot = Group(id: rootID, name: "根", items: [.group(renamedChild)])

        #expect(resolve([rootID, childID], in: [changedRoot]) == .group(renamedChild))
    }

    /// 当前组被删除：无法解析，面板收起
    @Test
    func deletedCurrentGroupResolvesToNil() {
        let prunedRoot = Group(id: rootID, name: "根", items: [app])

        #expect(resolve([rootID, childID], in: [prunedRoot]) == nil)
    }

    /// 当前组被移到别处，不再位于这个根组之下：无法解析
    @Test
    func movedCurrentGroupResolvesToNil() {
        let prunedRoot = Group(id: rootID, name: "根", items: [app])
        let otherRoot = Group(id: UUID(), name: "别处", items: [.group(child)])

        #expect(resolve([rootID, childID], in: [prunedRoot, otherRoot]) == nil)
    }

    /// 根组被删除或拖成子组，或路径为空：无法解析
    @Test
    func missingRootResolvesToNil() {
        let otherRoot = Group(id: UUID(), name: "别处", items: [.group(root)])

        #expect(resolve([rootID], in: [otherRoot]) == nil)
        #expect(resolve([], in: [root]) == nil)
    }

    // MARK: 访达文件夹

    /// 组 → 访达文件夹 → 其中的访达文件夹逐层解析，每一层读出的是那个目录的内容
    @Test
    func resolvesFinderFolderLevels() throws {
        let finderFolder = try finderFolderReference("资料")
        let rootGroups = [rootWith(finderFolder)]

        let first = try #require(resolve([rootID, finderFolder.id], in: rootGroups))

        #expect(first.id == finderFolder.id)
        #expect(names(of: first.items) == ["2024", "说明.txt"])
        #expect(first.cellCount == 3)

        let subdirectoryID = try #require(first.items.first?.id)
        let second = try #require(
            resolve([rootID, finderFolder.id, subdirectoryID], in: rootGroups)
        )

        #expect(second.id == subdirectoryID)
        #expect(names(of: second.items) == ["报告.txt"])
        #expect(second.finderFolderURL?.lastPathComponent == "2024")
    }

    /// 访达文件夹这一项已从所在的组里删除：无法解析
    @Test
    func removedFinderFolderItemResolvesToNil() throws {
        let finderFolder = try finderFolderReference("资料")

        #expect(resolve([rootID, finderFolder.id], in: [root]) == nil)
    }

    /// 访达文件夹在磁盘上被删除：无法解析
    @Test
    func deletedFinderFolderResolvesToNil() throws {
        let finderFolder = try finderFolderReference("资料")

        try FileManager.default.removeItem(at: directory.appending(path: "资料"))

        #expect(resolve([rootID, finderFolder.id], in: [rootWith(finderFolder)]) == nil)
    }

    /// 访达文件夹读不出内容（没有权限）：无法解析
    @Test
    func unreadableFinderFolderResolvesToNil() throws {
        let finderFolder = try finderFolderReference("资料")
        let path = directory.appending(path: "资料").path(percentEncoded: false)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)

        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        }

        #expect(resolve([rootID, finderFolder.id], in: [rootWith(finderFolder)]) == nil)
    }

    /// 访达文件夹按书签跟到了新位置：按新 URL 读，其中各项的 id 不变，深处的层级照常解析
    @Test
    func finderFolderWithNewURLIsReadFromNewLocation() throws {
        let finderFolder = try finderFolderReference("资料")
        let first = try #require(resolve([rootID, finderFolder.id], in: [rootWith(finderFolder)]))
        let subdirectoryID = try #require(first.items.first?.id)

        try FileManager.default.moveItem(
            at: directory.appending(path: "资料"),
            to: directory.appending(path: "旧资料")
        )

        // 模拟按书签跟到新位置：id 不变，URL 换成新位置
        let relocated = FileReference(
            id: finderFolder.id,
            url: URL(filePath: path(of: "旧资料"), directoryHint: .isDirectory),
            bookmark: nil
        )

        let second = try #require(
            resolve([rootID, relocated.id, subdirectoryID], in: [rootWith(relocated)])
        )

        #expect(names(of: second.items) == ["报告.txt"])
        #expect(second.finderFolderURL?.deletingLastPathComponent().lastPathComponent == "旧资料")
    }
}

// MARK: - Private

extension GroupPanelNavigationTests {
    /// 按本用例的一次展开解析导航路径
    private func resolve(_ path: [UUID], in rootGroups: [Group]) -> GroupPanelLevelContent? {
        GroupPanelController.levelContent(at: path, in: rootGroups) {
            try? finderFolderContents.items(of: $0, includingHiddenFiles: false)
        }
    }

    /// 临时目录里某个目录经分类后成为的文件项
    private func finderFolderReference(_ name: String) throws -> FileReference {
        let item = GroupItem(url: directory.appending(path: name), title: nil)
        let file: FileReference? = if case .file(let file) = item { file } else { nil }

        return try #require(file, "访达文件夹应当是文件：\(String(describing: item))")
    }

    /// 根组里放着 App、子组与给定的访达文件夹
    private func rootWith(_ finderFolder: FileReference) -> Group {
        Group(id: rootID, name: "根", items: [app, .group(child), .file(finderFolder)])
    }

    /// 各项的文件名
    private func names(of items: [GroupItem]) -> [String] {
        items.compactMap {
            guard case .file(let file) = $0 else { return nil }

            return file.url.lastPathComponent
        }
    }

    /// 临时目录里某一项的 POSIX 路径
    private func path(of name: String) -> String {
        directory.appending(path: name).path(percentEncoded: false)
    }
}
