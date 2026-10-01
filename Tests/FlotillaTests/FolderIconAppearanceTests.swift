import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderIconAppearanceTests

/// 文件夹图标跟随系统外观：外观归类为深浅两种，面板网格里的文件夹图标在外观变化时立即换成对应外观的底板
@MainActor
struct FolderIconAppearanceTests {
    /// 空的子文件夹：图标只有底板，深浅两种外观的画面必然不同
    private let subfolder = Folder(id: UUID(), name: "子文件夹", items: [])

    /// 基础外观与高对比度、vibrant 等变体都按最接近的深色或浅色取底板颜色
    @Test
    func appearanceVariantsMapToNearestBase() throws {
        let cases: [(NSAppearance.Name, FolderIconAppearance)] = [
            (.darkAqua, .dark),
            (.aqua, .light),
            (.accessibilityHighContrastDarkAqua, .dark),
            (.accessibilityHighContrastAqua, .light),
            (.vibrantDark, .dark),
            (.vibrantLight, .light),
        ]

        for (name, expected) in cases {
            let appearance = try #require(NSAppearance(named: name))

            #expect(FolderIconAppearance(appearance) == expected)
        }
    }

    /// 面板网格里子文件夹的图标随网格的外观切换，来回切换都立即生效
    @Test
    func gridFolderIconFollowsAppearance() throws {
        let layout = FolderGridLayout(
            itemCount: 1,
            availableSize: CGSize(width: 10_000, height: 10_000)
        )

        let grid = FolderGridView(
            items: [.folder(subfolder)],
            layout: layout,
            previewIconCount: 4,
            fileThumbnailLoader: nil,
            openInFinderHandler: nil
        ) { _ in }

        // 单元格在排版时才建
        grid.layoutSubtreeIfNeeded()

        let itemView = try #require(
            grid.subviews.compactMap { $0 as? FolderGridItemView }.first
        )

        for (name, expected) in Self.switches {
            grid.appearance = NSAppearance(named: name)

            #expect(
                itemView.icon.tiffRepresentation
                    == expectedIcon(appearance: expected, pointSize: FolderPanelMetrics.iconSize)
            )
        }
    }

    /// 滚动时才建的子文件夹单元格按建的时候的外观渲染：外观在它建出之前变过，也不会留着旧外观的底板
    @Test
    func laterBuiltFolderIconUsesCurrentAppearance() throws {
        // 7 列 8 行，面板显示 5 行：最后两行起初不建
        let items = Array(repeating: FolderItem.folder(subfolder), count: 56)

        let layout = FolderGridLayout(
            itemCount: items.count,
            availableSize: CGSize(width: 10_000, height: 10_000)
        )

        let scrollView = NSScrollView(frame: CGRect(
            x: 0,
            y: 0,
            width: layout.gridSize.width,
            height: CGFloat(layout.visibleRowCount) * FolderPanelMetrics.cellSize
        ))

        let grid = FolderGridView(
            items: items,
            layout: layout,
            previewIconCount: 4,
            fileThumbnailLoader: nil,
            openInFinderHandler: nil
        ) { _ in }

        scrollView.documentView = grid
        grid.appearance = NSAppearance(named: .darkAqua)
        scrollView.layoutSubtreeIfNeeded()

        // 外观变浅之后再滚到底，最后一格这时才建
        grid.appearance = NSAppearance(named: .aqua)

        let clipView = scrollView.contentView

        clipView.scroll(to: CGPoint(
            x: 0,
            y: grid.bounds.height - clipView.bounds.height
        ))

        let lastFrame = try #require(layout.cellFrames.last)
        let lastItemView = try #require(
            grid.subviews
                .compactMap { $0 as? FolderGridItemView }
                .first { $0.frame == lastFrame }
        )

        #expect(
            lastItemView.icon.tiffRepresentation
                == expectedIcon(appearance: .light, pointSize: FolderPanelMetrics.iconSize)
        )
    }
}

// MARK: - Private

extension FolderIconAppearanceTests {
    /// 依次切换的外观与期望的底板：深、浅、深，每一步都是一次真实的外观变化
    private static let switches: [(NSAppearance.Name, FolderIconAppearance)] = [
        (.darkAqua, .dark),
        (.aqua, .light),
        (.darkAqua, .dark),
    ]

    /// 直接按指定外观渲染的空子文件夹图标，作为视图里图标的期望画面
    private func expectedIcon(appearance: FolderIconAppearance, pointSize: CGFloat) -> Data? {
        FolderIconRenderer.render(
            folder: subfolder,
            previewIconCount: 4,
            pointSize: pointSize,
            appearance: appearance
        )
        .tiffRepresentation
    }
}
