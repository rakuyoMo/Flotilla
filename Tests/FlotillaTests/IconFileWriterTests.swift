import AppKit
import Testing

@testable import Flotilla

// MARK: - IconFileWriterTests

/// `.icns` 写入：Dock 按 tile 尺寸与屏幕倍率挑选表示，文件必须包含多档尺寸
///
/// 放在主线程串行执行：并发栅格化同一个 App 图标时，偶尔会画出不同的像素
@MainActor
final class IconFileWriterTests {
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

    /// 写出的文件能被读回，并且包含 16 到 1024 像素的多档表示
    @Test
    func writtenFileContainsAllSizes() throws {
        let url = directory.appending(path: "Icon.icns")

        try IconFileWriter.write(makeIcon(), to: url)

        let image = try #require(NSImage(contentsOf: url))
        let pixelWidths = Set(image.representations.map(\.pixelsWide))

        #expect(pixelWidths.isSuperset(of: [16, 32, 64, 128, 256, 512, 1024]))
    }

    /// 同一张图写两次，文件逐字节相同：stub 靠比对文件内容判断图标是否变化，内容不稳定会让 Dock 无谓地重启
    @Test
    func sameImageProducesIdenticalFiles() throws {
        let icon = makeIcon()
        let firstURL = directory.appending(path: "First.icns")
        let secondURL = directory.appending(path: "Second.icns")

        try IconFileWriter.write(icon, to: firstURL)
        try IconFileWriter.write(icon, to: secondURL)

        #expect(try Data(contentsOf: firstURL) == Data(contentsOf: secondURL))
    }

    /// 渲染一个带两个 App 预览的文件夹图标
    private func makeIcon() -> NSImage {
        let apps = ["Calculator", "Chess"].map {
            GroupItem.app(AppReference(
                id: UUID(),
                url: URL(filePath: "/System/Applications/\($0).app"),
                bookmark: nil,
                bundleIdentifier: nil
            ))
        }

        return GroupIconRenderer.render(
            group: Group(id: UUID(), name: "测试", items: apps),
            previewIconCount: 4,
            pointSize: 512,
            appearance: .light
        )
    }
}
