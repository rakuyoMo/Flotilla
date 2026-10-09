import AppKit
import Testing

@testable import Flotilla

// MARK: - IconFileComparatorTests

/// stub 图标按像素比对：预览里的 App 图标在系统缓存重新生成后会差一两级，这种差别不能让 stub 改写、Dock 重启；
/// 组图标的内容真的变了，又必须改写
///
/// 在主线程执行：`GroupIconRenderer.render` 要在主线程调用
@MainActor
final class IconFileComparatorTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(
            path: "FlotillaTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

    /// 创建本用例的临时目录
    init() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 同一个组图标写两次，按相同处理
    @Test
    func sameGroupIconIsEquivalent() throws {
        let icon = makeGroupIcon(appNames: ["Calculator", "Chess"])

        let first = try iconFileData(of: icon)
        let second = try iconFileData(of: icon)

        #expect(IconFileComparator.isEquivalent(first, second))
    }

    /// 各分量只差 1 级、或正好差到容差上限，文件字节不同，仍按相同处理
    @Test(arguments: [1, IconFileComparator.componentTolerance])
    func differenceWithinToleranceIsEquivalent(difference: Int) throws {
        let original = try iconFileData(of: SolidColorIcon.make(red: 100))
        let shifted = try iconFileData(of: SolidColorIcon.make(red: 100 + difference))

        try #require(original != shifted)

        #expect(IconFileComparator.isEquivalent(original, shifted))
    }

    /// 差值超过容差，按不同处理
    @Test
    func differenceBeyondToleranceIsNotEquivalent() throws {
        let original = try iconFileData(of: SolidColorIcon.make(red: 100))
        let shifted = try iconFileData(
            of: SolidColorIcon.make(red: 100 + IconFileComparator.componentTolerance + 1)
        )

        #expect(!IconFileComparator.isEquivalent(original, shifted))
    }

    /// 组图标的内容真的变了：预览换顺序、少一项、预览数量变化、换外观、某一格换成别的图标，都按不同处理
    @Test(arguments: [
        (["Chess", "Calculator"], 4, GroupIconAppearance.light),
        (["Calculator"], 4, .light),
        (["Calculator", "Chess"], 1, .light),
        (["Calculator", "Chess"], 4, .dark),
        (["Calculator", "Stickies"], 4, .light),
    ])
    func contentChangeIsNotEquivalent(
        appNames: [String],
        previewIconCount: Int,
        appearance: GroupIconAppearance
    ) throws {
        let original = try iconFileData(of: makeGroupIcon(appNames: ["Calculator", "Chess"]))

        let changed = try iconFileData(
            of: makeGroupIcon(
                appNames: appNames,
                previewIconCount: previewIconCount,
                appearance: appearance
            )
        )

        #expect(!IconFileComparator.isEquivalent(original, changed))
    }

    /// 解不出图像的数据按不同处理：现有图标损坏时 stub 要重新生成
    @Test
    func unreadableDataIsNotEquivalent() throws {
        let icon = try iconFileData(of: SolidColorIcon.make(red: 100))

        #expect(!IconFileComparator.isEquivalent(Data("not an icon".utf8), icon))
    }

    /// 按 stub 的流程把图像写成 `.icns`，返回文件内容
    private func iconFileData(of image: NSImage) throws -> Data {
        let url = directory.appending(path: "\(UUID().uuidString).icns")

        try IconFileWriter.write(image, to: url)

        return try Data(contentsOf: url)
    }

    /// 渲染由这些系统 App 组成的组图标
    private func makeGroupIcon(
        appNames: [String],
        previewIconCount: Int = 4,
        appearance: GroupIconAppearance = .light
    ) -> NSImage {
        let apps = appNames.map {
            GroupItem.app(AppReference(
                id: UUID(),
                url: URL(filePath: "/System/Applications/\($0).app"),
                bookmark: nil,
                bundleIdentifier: nil
            ))
        }

        return GroupIconRenderer.render(
            group: Group(id: UUID(), name: "测试", items: apps),
            previewIconCount: previewIconCount,
            pointSize: 512,
            appearance: appearance
        )
    }
}
