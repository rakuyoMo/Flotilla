import AppKit
import Testing

@testable import Flotilla

// MARK: - GroupIconAppearanceTests

/// 组图标跟随系统外观：外观归类为深浅两种，面板网格里的组图标在外观变化时立即换成对应外观的底板
@MainActor
struct GroupIconAppearanceTests {
    /// 空的子组：图标只有底板，深浅两种外观的画面必然不同
    private let subgroup = Group(id: UUID(), name: "子组", items: [])

    /// 基础外观与高对比度、vibrant 等变体都按最接近的深色或浅色取底板颜色
    @Test
    func appearanceVariantsMapToNearestBase() throws {
        let cases: [(NSAppearance.Name, GroupIconAppearance)] = [
            (.darkAqua, .dark),
            (.aqua, .light),
            (.accessibilityHighContrastDarkAqua, .dark),
            (.accessibilityHighContrastAqua, .light),
            (.vibrantDark, .dark),
            (.vibrantLight, .light),
        ]

        for (name, expected) in cases {
            let appearance = try #require(NSAppearance(named: name))

            #expect(GroupIconAppearance(appearance) == expected)
        }
    }

    /// 面板网格里子组的图标随网格的外观切换，来回切换都立即生效
    @Test
    func gridGroupIconFollowsAppearance() throws {
        let layout = GroupGridLayout(
            itemCount: 1,
            availableSize: CGSize(width: 10_000, height: 10_000)
        )

        let grid = GroupGridView(
            items: [.group(subgroup)],
            layout: layout,
            previewIconCount: 4,
            hiddenItemIDs: [],
            fileThumbnailLoader: nil,
            openInFinderHandler: nil
        ) { _ in }

        // 单元格在排版时才建
        grid.layoutSubtreeIfNeeded()

        let itemView = try #require(
            grid.subviews.compactMap { $0 as? GroupGridItemView }.first
        )

        for (name, expected) in Self.switches {
            grid.appearance = NSAppearance(named: name)

            #expect(
                itemView.icon.tiffRepresentation
                    == expectedIcon(appearance: expected, pointSize: GroupPanelMetrics.iconSize)
            )
        }
    }

    /// 滚动时才建的子组单元格按建的时候的外观渲染：外观在它建出之前变过，也不会留着旧外观的底板
    @Test
    func laterBuiltGroupIconUsesCurrentAppearance() throws {
        // 7 列 8 行，面板显示 5 行：最后两行起初不建
        let items = Array(repeating: GroupItem.group(subgroup), count: 56)

        let layout = GroupGridLayout(
            itemCount: items.count,
            availableSize: CGSize(width: 10_000, height: 10_000)
        )

        let scrollView = NSScrollView(frame: CGRect(
            x: 0,
            y: 0,
            width: layout.gridSize.width,
            height: CGFloat(layout.visibleRowCount) * GroupPanelMetrics.cellSize
        ))

        let grid = GroupGridView(
            items: items,
            layout: layout,
            previewIconCount: 4,
            hiddenItemIDs: [],
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
                .compactMap { $0 as? GroupGridItemView }
                .first { $0.frame == lastFrame }
        )

        #expect(
            lastItemView.icon.tiffRepresentation
                == expectedIcon(appearance: .light, pointSize: GroupPanelMetrics.iconSize)
        )
    }
}

// MARK: - Private

extension GroupIconAppearanceTests {
    /// 依次切换的外观与期望的底板：深、浅、深，每一步都是一次真实的外观变化
    private static let switches: [(NSAppearance.Name, GroupIconAppearance)] = [
        (.darkAqua, .dark),
        (.aqua, .light),
        (.darkAqua, .dark),
    ]

    /// 直接按指定外观渲染的空子组的图标，作为视图里图标的期望画面
    private func expectedIcon(appearance: GroupIconAppearance, pointSize: CGFloat) -> Data? {
        GroupIconRenderer.render(
            group: subgroup,
            previewIconCount: 4,
            pointSize: pointSize,
            appearance: appearance
        )
        .tiffRepresentation
    }
}
