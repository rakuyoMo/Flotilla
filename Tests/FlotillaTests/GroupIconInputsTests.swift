import Foundation
import Testing

@testable import Flotilla

// MARK: - GroupIconInputsTests

/// 组图标的输入：只有改变预览的改动才让输入变化
///
/// 输入没变的根组，同步时不重新渲染图标、不改写 stub，Dock 也不因此重启
struct GroupIconInputsTests {
    /// 组里的六个 App，预览数量为 4 时前四个参与预览
    private let apps = (0 ..< 6).map { Self.makeApp(index: $0) }

    /// 只动预览之外的项：调整第 5 项之后的顺序、删除或追加预览之外的项，输入都不变
    @Test
    func itemsBeyondPreviewKeepInputs() {
        let original = inputs(of: apps)

        let reordered = inputs(of: Array(apps.prefix(4)) + [apps[5], apps[4]])
        let removed = inputs(of: Array(apps.prefix(5)))
        let appended = inputs(of: apps + [Self.makeApp(index: 6)])

        #expect(reordered == original)
        #expect(removed == original)
        #expect(appended == original)
    }

    /// 子组不参与预览：子组里的改动、子组挪到预览的项之间，输入都不变
    @Test
    func subgroupChangesKeepInputs() {
        let subgroupID = UUID()
        let subgroup = GroupItem.group(Group(id: subgroupID, name: "子组", items: []))

        let changedSubgroup = GroupItem.group(
            Group(id: subgroupID, name: "改名的子组", items: [apps[0]])
        )

        let original = inputs(of: [subgroup] + apps)

        let changed = inputs(of: [changedSubgroup] + apps)
        let moved = inputs(of: [apps[0], subgroup] + apps.dropFirst())

        #expect(changed == original)
        #expect(moved == original)
    }

    /// 预览数量变了、取到的项没变，输入不变：只有三项的组，预览数量 3 与 4 画出同一个图标
    @Test
    func previewCountTakingSameItemsKeepsInputs() {
        let group = Group(id: UUID(), name: "三项", items: Array(apps.prefix(3)))

        let three = GroupIconInputs(group: group, previewIconCount: 3, appearance: .light)
        let four = GroupIconInputs(group: group, previewIconCount: 4, appearance: .light)

        #expect(three == four)
    }

    /// 改变预览的改动让输入变化：前几项换序、某一格换成别的项、删掉预览里的一项
    @Test
    func previewChangesChangeInputs() {
        let original = inputs(of: apps)

        let reordered = inputs(of: [apps[1], apps[0]] + apps.dropFirst(2))
        let replaced = inputs(of: [Self.makeApp(index: 6)] + apps.dropFirst())
        let removed = inputs(of: Array(apps.dropFirst()))

        #expect(reordered != original)
        #expect(replaced != original)
        #expect(removed != original)
    }

    /// 预览数量变了、取到的项也变了，输入变化
    @Test
    func previewCountTakingOtherItemsChangesInputs() {
        let group = Group(id: UUID(), name: "六项", items: apps)

        let three = GroupIconInputs(group: group, previewIconCount: 3, appearance: .light)
        let four = GroupIconInputs(group: group, previewIconCount: 4, appearance: .light)

        #expect(three != four)
    }

    /// 外观变了，底板颜色随之变化，输入变化
    @Test
    func appearanceChangesInputs() {
        let group = Group(id: UUID(), name: "六项", items: apps)

        let light = GroupIconInputs(group: group, previewIconCount: 4, appearance: .light)
        let dark = GroupIconInputs(group: group, previewIconCount: 4, appearance: .dark)

        #expect(light != dark)
    }
}

// MARK: - Private

extension GroupIconInputsTests {
    /// 第 index 个测试用的 App 项：只比较值，不读取图标，路径不必存在
    private static func makeApp(index: Int) -> GroupItem {
        .app(AppReference(
            id: UUID(),
            url: URL(filePath: "/Applications/App \(index).app"),
            bookmark: nil,
            bundleIdentifier: nil
        ))
    }

    /// 预览数量为 4、浅色外观时，由这些项组成的组的图标输入
    private func inputs(of items: [GroupItem]) -> GroupIconInputs {
        GroupIconInputs(
            group: Group(id: UUID(), name: "测试", items: items),
            previewIconCount: 4,
            appearance: .light
        )
    }
}
