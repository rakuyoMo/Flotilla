import AppKit
import Testing

@testable import Flotilla

// MARK: - FinderFolderIconStoreTests

/// 组里的访达文件夹按访达里的实际外观显示：上了色的是系统画好的那种颜色，没上色的、换过自定义图标的与 `NSWorkspace` 的图标逐像素相同；
/// 外观变了 1 s 内换上新图并通知各处，只是其它属性变了、不在组里了都不重取，免得 Dock 白白重启
@MainActor
final class FinderFolderIconStoreTests {
    /// 本用例独占的临时目录：组树的持久化文件与测试用的文件夹都在这里
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例的组树：一个根组 “资料”
    private let store: GroupStore

    /// 假的取图，监听的用例用它数取图的次数
    private let generator = FinderFolderIconGeneratorStub()

    /// 建立组树与根组
    init() {
        store = GroupStore(fileURL: directory.appending(path: "folders.json"))

        _ = store.addRootGroup(named: "资料")
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

// MARK: - Quick Look

extension FinderFolderIconStoreTests {
    /// 打了红色标签的访达文件夹：设置窗口与面板的 1 倍、2 倍下，文件夹正面中央都是红色
    @Test(
        .enabled(if: FinderFolderAppearance.isSupported),
        arguments: [
            (20, 1),
            (20, 2),
            (GroupPanelMetrics.iconSize, 1),
            (GroupPanelMetrics.iconSize, 2),
        ] as [(CGFloat, CGFloat)]
    )
    func redTaggedFolderIsRed(side: CGFloat, scale: CGFloat) async throws {
        let folder = try addFolder(named: "红色", tags: ["红色\n6"])
        let iconStore = FinderFolderIconStore(store: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        #expect(await updates.wait(forIconOf: folder))

        let color = try IconPixels.centerColor(of: iconStore.icon(of: folder), side: side, scale: scale)

        #expect(color.red - color.green > 100)
        #expect(color.red - color.blue > 100)
    }

    /// 没上色的、换过自定义图标的访达文件夹：不向 QuickLook 取，与 `NSWorkspace` 的图标逐像素相同
    @Test
    func plainAndCustomIconFoldersKeepWorkspaceIcon() async throws {
        let plain = try addFolder(named: "没上色", tags: [])
        let custom = try addFolder(named: "自定义图标", tags: ["红色\n6"])

        let caution = try #require(NSImage(named: NSImage.cautionName))

        try #require(
            NSWorkspace.shared.setIcon(
                caution,
                forFile: custom.url.path(percentEncoded: false),
                options: []
            )
        )

        let iconStore = FinderFolderIconStore(store: store)

        iconStore.start()

        for folder in [plain, custom] {
            let workspaceIcon = NSWorkspace.shared.icon(forFile: folder.url.path(percentEncoded: false))

            #expect(!iconStore.isLoadingIcon(of: folder))
            #expect(iconStore.iconVersion(of: folder) == nil)

            for scale: CGFloat in [1, 2] {
                #expect(
                    try IconPixels.pixels(of: iconStore.icon(of: folder), side: 20, scale: scale)
                        == IconPixels.pixels(of: workspaceIcon, side: 20, scale: scale)
                )
            }
        }
    }

    /// 只有 emoji、没有标签的访达文件夹同样向 QuickLook 取，画出来与 `NSWorkspace` 的蓝色文件夹不同
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func emojiFolderUsesQuickLookIcon() async throws {
        let folder = try addFolder(named: "披萨", tags: [])

        try FinderFolderAttributes.setSymbolOrEmoji(#"{"emoji":"🍕"}"#, of: folder.url)

        let iconStore = FinderFolderIconStore(store: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        #expect(await updates.wait(forIconOf: folder))

        let workspaceIcon = NSWorkspace.shared.icon(forFile: folder.url.path(percentEncoded: false))

        #expect(
            try IconPixels.pixels(of: iconStore.icon(of: folder), side: 20, scale: 2)
                != IconPixels.pixels(of: workspaceIcon, side: 20, scale: 2)
        )
    }
}

// MARK: - Watching

extension FinderFolderIconStoreTests {
    /// 取完之前还在取图，Dock 同步据此等它；取完后不再是
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func loadingUntilIconArrives() async throws {
        let folder = try addFolder(named: "红色", tags: ["红色\n6"])
        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        #expect(iconStore.isLoadingIcon(of: folder))
        #expect(await updates.wait(forUpdatesAt: FinderFolderIconStore.folderPath(of: folder)))
        #expect(!iconStore.isLoadingIcon(of: folder))
    }

    /// QuickLook 迟迟不回：2 s 后不再算取图中，发出通知，让推迟了的 Dock 同步按当前的图补上；
    /// 结果之后到了照常换上，再发一次通知
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func slowLoadStopsBlockingAfterLimit() async throws {
        let folder = try addFolder(named: "红色", tags: ["红色\n6"])
        let path = FinderFolderIconStore.folderPath(of: folder)
        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)
        let startedAt = ContinuousClock.now

        generator.completesImmediately = false
        iconStore.start()

        #expect(iconStore.isLoadingIcon(of: folder))

        // 250 轮至少 5 s，比上限长得多
        try #require(await updates.wait(forUpdatesAt: path, rounds: 250))

        #expect(ContinuousClock.now - startedAt >= .seconds(2))
        #expect(!iconStore.isLoadingIcon(of: folder))
        #expect(iconStore.iconVersion(of: folder) == nil)

        generator.completeHeldRequests()

        #expect(await updates.wait(forUpdatesAt: path, count: 2))
        #expect(iconStore.iconVersion(of: folder) != nil)
        #expect(!iconStore.isLoadingIcon(of: folder))
    }

    /// 子组里的访达文件夹同样监听、取图
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func subgroupFoldersAreWatched() async throws {
        let root = try #require(store.rootGroups.first)
        let subgroup = try #require(store.addSubgroup(named: "子组", to: root.id))
        let folder = try addFolder(named: "红色", tags: ["红色\n6"], to: subgroup.id)

        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        #expect(await updates.wait(forUpdatesAt: FinderFolderIconStore.folderPath(of: folder)))
        #expect(generator.requestedURLs.count == 1)
    }

    /// 运行中改了标签：1 s 内换上新图、通知带上这个文件夹，图的版本随之换掉
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func tagChangeReloadsIcon() async throws {
        let folder = try addFolder(named: "红色", tags: ["红色\n6"])
        let path = FinderFolderIconStore.folderPath(of: folder)
        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        try #require(await updates.wait(forUpdatesAt: path))

        let redIcon = iconStore.icon(of: folder)
        let redVersion = try #require(iconStore.iconVersion(of: folder))

        try FinderFolderAttributes.setTags(["绿色\n2"], of: folder.url)

        // 50 轮至少 1 s：单独跑时就是 1 s 之内
        #expect(await updates.wait(forUpdatesAt: path, count: 2, rounds: 50))
        #expect(iconStore.icon(of: folder) !== redIcon)
        #expect(generator.requestedURLs.count == 2)

        let greenVersion = try #require(iconStore.iconVersion(of: folder))

        #expect(greenVersion != redVersion)
    }

    /// 去掉标签：不再向 QuickLook 取，退回 `NSWorkspace` 的图标，同样通知
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func removingTagFallsBackToWorkspaceIcon() async throws {
        let folder = try addFolder(named: "红色", tags: ["红色\n6"])
        let path = FinderFolderIconStore.folderPath(of: folder)
        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        try #require(await updates.wait(forUpdatesAt: path))

        try FinderFolderAttributes.setTags([], of: folder.url)

        #expect(await updates.wait(forUpdatesAt: path, count: 2, rounds: 50))
        #expect(iconStore.iconVersion(of: folder) == nil)
        #expect(generator.requestedURLs.count == 1)
    }

    /// 只是权限变了：外观没变，不重取图、不通知，图还是原来那张
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func unrelatedAttributeChangeKeepsIcon() async throws {
        let folder = try addFolder(named: "红色", tags: ["红色\n6"])
        let path = FinderFolderIconStore.folderPath(of: folder)
        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        try #require(await updates.wait(forUpdatesAt: path))

        let icon = iconStore.icon(of: folder)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: folder.url.path(percentEncoded: false)
        )

        // 30 轮至少 0.6 s，等过合并间隔与重读外观：要发的通知这时一定已经发了
        #expect(await !updates.wait(forUpdatesAt: path, count: 2, rounds: 30))
        #expect(updates.paths == [path])
        #expect(generator.requestedURLs.count == 1)
        #expect(iconStore.icon(of: folder) === icon)
    }

    /// 从组里拿掉之后停止监听：再改标签不取图、不通知，缓存也已丢掉
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func removedFolderIsNoLongerWatched() async throws {
        let folder = try addFolder(named: "红色", tags: ["红色\n6"])
        let path = FinderFolderIconStore.folderPath(of: folder)
        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        try #require(await updates.wait(forUpdatesAt: path))

        store.remove(itemID: folder.id)

        try FinderFolderAttributes.setTags(["绿色\n2"], of: folder.url)

        #expect(await !updates.wait(forUpdatesAt: path, count: 2, rounds: 30))
        #expect(updates.paths == [path])
        #expect(generator.requestedURLs.count == 1)
        #expect(iconStore.iconVersion(of: folder) == nil)
    }

    /// 原路径上的文件夹被换掉（挪走后在原处放了打着别的颜色标签的新文件夹）：换上新文件夹的图；
    /// 之后改的是新文件夹的标签，照样察觉得到
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func replacedFolderIsWatchedInstead() async throws {
        let folder = try addFolder(named: "红色", tags: ["红色\n6"])
        let path = FinderFolderIconStore.folderPath(of: folder)
        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        try #require(await updates.wait(forUpdatesAt: path))

        let redVersion = try #require(iconStore.iconVersion(of: folder))

        try moveAway(folder)
        try makeFolder(at: folder.url, tags: ["绿色\n2"])

        #expect(await updates.wait(forUpdatesAt: path, count: 2))
        #expect(generator.requestedURLs.count == 2)

        let greenVersion = try #require(iconStore.iconVersion(of: folder))

        #expect(greenVersion != redVersion)

        // 监听的已是新文件夹
        try FinderFolderAttributes.setTags(["紫色\n3"], of: folder.url)

        #expect(await updates.wait(forUpdatesAt: path, count: 3))
        #expect(generator.requestedURLs.count == 3)
    }

    /// 文件夹挪走后原路径上没有东西：丢掉旧图；之后在原处放了新文件夹，没有监听、收不到事件，
    /// 组树一变就核对出来，接上监听、换上新文件夹的图
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func folderAppearingAtPathIsWatchedOnTreeChange() async throws {
        let folder = try addFolder(named: "红色", tags: ["红色\n6"])
        let path = FinderFolderIconStore.folderPath(of: folder)
        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        try #require(await updates.wait(forUpdatesAt: path))

        try moveAway(folder)

        #expect(await updates.wait(forUpdatesAt: path, count: 2))
        #expect(iconStore.iconVersion(of: folder) == nil)

        try makeFolder(at: folder.url, tags: ["绿色\n2"])

        store.rename(groupID: try #require(store.rootGroups.first).id, to: "资料夹")

        #expect(await updates.wait(forUpdatesAt: path, count: 3))
        #expect(iconStore.iconVersion(of: folder) != nil)
        #expect(generator.requestedURLs.count == 2)

        // 接上了新文件夹的监听
        try FinderFolderAttributes.setTags(["紫色\n3"], of: folder.url)

        #expect(await updates.wait(forUpdatesAt: path, count: 4))
        #expect(generator.requestedURLs.count == 3)
    }

    /// QuickLook 取不出：退回 `NSWorkspace` 的图标，也算取完，照样通知
    @Test(.enabled(if: FinderFolderAppearance.isSupported))
    func failedLoadFallsBackAndFinishes() async throws {
        let folder = try addFolder(named: "红色", tags: ["红色\n6"])
        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        generator.generatesIcons = false
        iconStore.start()

        #expect(await updates.wait(forUpdatesAt: FinderFolderIconStore.folderPath(of: folder)))
        #expect(!iconStore.isLoadingIcon(of: folder))
        #expect(iconStore.iconVersion(of: folder) == nil)
    }
}

// MARK: - Private

extension FinderFolderIconStoreTests {
    /// 在临时目录里新建一个文件夹、打上标签，加进组里
    /// - Parameters:
    ///   - name: 文件夹名
    ///   - tags: 标签，每项是 “名称\n颜色号”；为空时不打
    ///   - groupID: 加进哪个组；为 nil 时加进根组 “资料”
    /// - Returns: 组里这个访达文件夹的引用
    private func addFolder(
        named name: String,
        tags: [String],
        to groupID: UUID? = nil
    ) throws -> FileReference {
        let url = directory.appending(path: name, directoryHint: .isDirectory)

        try makeFolder(at: url, tags: tags)

        let item = try #require(GroupItem(url: url, title: nil))
        let targetID = try groupID ?? #require(store.rootGroups.first).id

        store.addItems([item], to: targetID)

        guard case .file(let file) = item else {
            Issue.record("访达文件夹没有分类成文件")
            throw CancellationError()
        }

        return file
    }

    /// 在给定的位置新建一个文件夹、打上标签
    /// - Parameters:
    ///   - url: 文件夹的位置，在本用例的临时目录里
    ///   - tags: 标签，每项是 “名称\n颜色号”；为空时不打
    private func makeFolder(at url: URL, tags: [String]) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FinderFolderAttributes.setTags(tags, of: url)
    }

    /// 把组里的访达文件夹挪到临时目录里的另一个位置，原路径上不再有东西
    /// - Parameter folder: 组里的访达文件夹
    private func moveAway(_ folder: FileReference) throws {
        try FileManager.default.moveItem(
            at: folder.url,
            to: directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        )
    }
}
