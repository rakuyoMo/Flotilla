import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderPanelNavigationTests

/// 导航路径的解析：展示期间文件夹树变化时，当前层级还在就保留，当前文件夹不在该根文件夹之下就收起
@MainActor
struct FolderPanelNavigationTests {
    /// 根文件夹的 id
    private let rootID = UUID()

    /// 子文件夹的 id
    private let childID = UUID()

    /// 最深一层的子文件夹
    private let grandchild = Folder(id: UUID(), name: "孙", items: [])

    /// 一个 App 项
    private let app = FolderItem.app(AppReference(
        id: UUID(),
        url: URL(filePath: "/System/Applications/Chess.app"),
        bookmark: nil
    ))

    /// 根文件夹下的子文件夹
    private var child: Folder {
        Folder(id: childID, name: "子", items: [.folder(grandchild)])
    }

    /// 根 → 子 → 孙
    private var root: Folder {
        Folder(id: rootID, name: "根", items: [app, .folder(child)])
    }

    /// 沿路径逐层找到当前层级
    @Test
    func resolvesEachLevelAlongPath() {
        let rootFolders = [root]
        let grandchildPath = [rootID, childID, grandchild.id]

        #expect(FolderPanelController.folder(at: [rootID], in: rootFolders) == root)
        #expect(FolderPanelController.folder(at: [rootID, childID], in: rootFolders) == child)
        #expect(FolderPanelController.folder(at: grandchildPath, in: rootFolders) == grandchild)
    }

    /// 当前层级的内容变化后，解析出的是变化后的文件夹，层级保持不变
    @Test
    func keepsLevelWhenContentChanges() {
        var renamedChild = child
        renamedChild.name = "改名后的子"
        renamedChild.items.append(app)

        let changedRoot = Folder(id: rootID, name: "根", items: [.folder(renamedChild)])
        let resolved = FolderPanelController.folder(at: [rootID, childID], in: [changedRoot])

        #expect(resolved == renamedChild)
    }

    /// 当前文件夹被删除：无法解析，面板收起
    @Test
    func deletedCurrentFolderResolvesToNil() {
        let prunedRoot = Folder(id: rootID, name: "根", items: [app])

        #expect(FolderPanelController.folder(at: [rootID, childID], in: [prunedRoot]) == nil)
    }

    /// 当前文件夹被移到别处，不再位于这个根文件夹之下：无法解析
    @Test
    func movedCurrentFolderResolvesToNil() {
        let prunedRoot = Folder(id: rootID, name: "根", items: [app])
        let otherRoot = Folder(id: UUID(), name: "别处", items: [.folder(child)])

        let resolved = FolderPanelController.folder(
            at: [rootID, childID],
            in: [prunedRoot, otherRoot]
        )

        #expect(resolved == nil)
    }

    /// 根文件夹被删除或拖成子文件夹：无法解析
    @Test
    func missingRootResolvesToNil() {
        let otherRoot = Folder(id: UUID(), name: "别处", items: [.folder(root)])

        #expect(FolderPanelController.folder(at: [rootID], in: [otherRoot]) == nil)
        #expect(FolderPanelController.folder(at: [], in: [root]) == nil)
    }
}
