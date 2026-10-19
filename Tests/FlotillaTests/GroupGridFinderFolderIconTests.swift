import AppKit
import Testing

@testable import Flotilla

// MARK: - GroupGridFinderFolderIconTests

/// 面板开着时访达文件夹取到新图：它自己的格就地换上，预览里有它的子组重画组图标，用的正是新图；
/// 预览里没有它的子组不重画
@MainActor
final class GroupGridFinderFolderIconTests {
    /// 本用例独占的临时目录：组树的持久化文件与测试用的文件夹都在这里
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例的组树
    private let store: GroupStore

    /// 假的取图：交出的是红色分量 255 的纯色图
    private let generator = FinderFolderIconGeneratorStub()

    /// 打了红色标签的访达文件夹
    private let finderFolder: FileReference

    /// 根组 “资料” 里依次是访达文件夹、预览里有它的子组、只有 App 的子组
    private let rootGroup: Group

    /// 建立组树与访达文件夹
    init() throws {
        store = GroupStore(fileURL: directory.appending(path: "folders.json"))

        let url = directory.appending(path: "红色", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FinderFolderAttributes.setTags(["红色\n6"], of: url)

        let item = try #require(GroupItem(url: url, title: nil))

        guard case .file(let file) = item else {
            Issue.record("访达文件夹没有分类成文件")
            throw CancellationError()
        }

        finderFolder = file

        let calculator = try #require(
            GroupItem(url: URL(filePath: "/System/Applications/Calculator.app"), title: nil)
        )

        // 访达文件夹先加，排在两个子组前面；子组里是同一个访达文件夹的另一项
        let root = store.addRootGroup(named: "资料")

        store.addItems([item], to: root.id)

        let withFolder = try #require(store.addSubgroup(named: "有访达文件夹", to: root.id))
        let withApp = try #require(store.addSubgroup(named: "只有 App", to: root.id))

        store.addItems([try #require(GroupItem(url: url, title: nil))], to: withFolder.id)
        store.addItems([calculator], to: withApp.id)

        rootGroup = try #require(store.rootGroups.first)
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 网格建好时还没取到图；取到之后访达文件夹的格换上新图，预览里有它的子组重画、预览那一格画的是新图
    @Test
    func newIconReachesCellAndSubgroupPreview() async throws {
        let iconStore = generator.makeIconStore(following: store)
        let updates = FinderFolderIconUpdateRecorder(of: iconStore)

        iconStore.start()

        let grid = makeGrid(showing: rootGroup, finderFolderIcons: iconStore)
        let before = icons(in: grid)

        try #require(before.count == 3)

        try #require(await updates.wait(forUpdatesAt: FinderFolderIconStore.folderPath(of: finderFolder)))

        let after = icons(in: grid)

        #expect(after[0] === iconStore.icon(of: finderFolder))
        #expect(after[0] !== before[0])
        #expect(after[1] !== before[1])
        #expect(after[2] === before[2])

        // 子组图标左上的预览格中央：假的取图交出的颜色（红 255、绿 128、蓝 64）
        let side = GroupPanelMetrics.iconSize
        let pixels = try IconPixels.pixels(of: after[1], side: side, scale: 1)
        let center = Int(side * 0.327)
        let base = (center * Int(side) + center) * 4

        #expect(pixels[base] > 200)
        #expect((100 ... 160).contains(pixels[base + 1]))
        #expect(pixels[base + 2] < 100)
    }
}

// MARK: - Private

extension GroupGridFinderFolderIconTests {
    /// 与面板相同的组的层级网格，排好版、单元格全部建出
    /// - Parameters:
    ///   - group: 这一层的组
    ///   - finderFolderIcons: 访达文件夹的图标
    private func makeGrid(
        showing group: Group,
        finderFolderIcons: FinderFolderIconStore
    ) -> GroupGridView {
        let layout = GroupGridLayout(
            itemCount: group.items.count,
            availableSize: CGSize(width: 2000, height: 2000)
        )

        let grid = GroupGridView(
            items: group.items,
            layout: layout,
            previewIconCount: 4,
            hiddenItemIDs: [],
            fileThumbnailLoader: nil,
            finderFolderIcons: finderFolderIcons,
            openInFinderHandler: nil
        ) { _ in }

        grid.layoutSubtreeIfNeeded()

        return grid
    }

    /// 各格当前显示的图标，按格的先后
    private func icons(in grid: GroupGridView) -> [NSImage] {
        grid.subviews
            .compactMap { $0 as? GroupGridItemView }
            .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            .map(\.icon)
    }
}
