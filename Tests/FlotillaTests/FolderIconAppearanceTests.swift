import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderIconAppearanceTests

/// 文件夹图标跟随系统外观：外观归类为深浅两种，面板网格与设置窗口树里的文件夹图标在外观变化时立即换成对应外观的底板
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
            previewIconCount: 4
        ) { _ in }

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

    /// 设置窗口树里文件夹行的图标随行视图的外观切换，来回切换都立即生效
    @Test
    func treeFolderIconFollowsAppearance() throws {
        let cell = FolderTreeCellView()
        cell.configure(
            with: FolderTreeNode(item: .folder(subfolder), parent: nil),
            previewIconCount: 4
        )

        for (name, expected) in Self.switches {
            cell.appearance = NSAppearance(named: name)

            let icon = try #require(cell.imageView?.image)

            #expect(
                icon.tiffRepresentation
                    == expectedIcon(appearance: expected, pointSize: icon.size.width)
            )
        }
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
