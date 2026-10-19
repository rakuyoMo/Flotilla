import AppKit
import Testing

@testable import Flotilla

// MARK: - FinderFolderAppearanceTests

/// 访达文件夹的外观按访达的规则读：访达给文件夹上的是最后一个带颜色的标签的颜色，无色标签不算；
/// 有 emoji 或符号的同样要向 QuickLook 取图；换过自定义图标的显示自定义图标，打了颜色标签也不着色
@MainActor
final class FinderFolderAppearanceTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 没有扩展属性的文件夹：没有颜色、emoji 与符号，图标照旧用 `NSWorkspace` 的
    @Test
    func plainFolderHasNoAppearance() throws {
        let appearance = try FinderFolderAppearance(folderAt: makeFolder(tags: []))

        #expect(appearance.tagColor == nil)
        #expect(appearance.symbolOrEmoji == nil)
        #expect(!appearance.hasCustomIcon)
        #expect(!appearance.needsQuickLookIcon)
    }

    /// 无色的标签不上色：颜色号是 0，或只有名称没写颜色号
    @Test(arguments: [["工作\n0"], ["红色"]])
    func colorlessTagsHaveNoColor(tags: [String]) throws {
        let appearance = try FinderFolderAppearance(folderAt: makeFolder(tags: tags))

        #expect(appearance.tagColor == nil)
        #expect(!appearance.needsQuickLookIcon)
    }

    /// 一个带颜色的标签：取它的颜色号；macOS 26 起图标向 QuickLook 取
    @Test
    func singleColoredTagGivesItsColor() throws {
        let appearance = try FinderFolderAppearance(folderAt: makeFolder(tags: ["红色\n6"]))

        #expect(appearance.tagColor == 6)
        #expect(appearance.needsQuickLookIcon == FinderFolderAppearance.isSupported)
    }

    /// 几个带颜色的标签取最后一个；颜色在前、无色在后时仍是那个颜色
    @Test(arguments: [
        (["红色\n6", "蓝色\n4"], 4),
        (["蓝色\n4", "红色\n6"], 6),
        (["红色\n6", "工作\n0"], 6),
        (["工作\n0", "绿色\n2"], 2),
    ])
    func lastColoredTagWins(tags: [String], color: Int) throws {
        let appearance = try FinderFolderAppearance(folderAt: makeFolder(tags: tags))

        #expect(appearance.tagColor == color)
    }

    /// 只有 emoji 或符号、没有标签：原样记下内容；macOS 26 起图标同样向 QuickLook 取
    @Test(arguments: [#"{"emoji":"🍕"}"#, #"{"sym":"star.fill"}"#])
    func symbolOrEmojiAloneNeedsQuickLook(json: String) throws {
        let folder = try makeFolder(tags: [])

        try FinderFolderAttributes.setSymbolOrEmoji(json, of: folder)

        let appearance = FinderFolderAppearance(folderAt: folder)

        #expect(appearance.symbolOrEmoji == Data(json.utf8))
        #expect(appearance.tagColor == nil)
        #expect(appearance.needsQuickLookIcon == FinderFolderAppearance.isSupported)
    }

    /// 换过自定义图标的文件夹：打了颜色标签也显示自定义图标，不向 QuickLook 取
    @Test
    func customIconOverridesColor() throws {
        let folder = try makeFolder(tags: ["红色\n6"])

        let caution = try #require(NSImage(named: NSImage.cautionName))

        try #require(
            NSWorkspace.shared.setIcon(
                caution,
                forFile: folder.path(percentEncoded: false),
                options: []
            )
        )

        let appearance = FinderFolderAppearance(folderAt: folder)

        #expect(appearance.hasCustomIcon)
        #expect(appearance.tagColor == 6)
        #expect(!appearance.needsQuickLookIcon)
    }

    /// 已删除的文件夹读不到扩展属性，当作没有
    @Test
    func deletedFolderHasNoAppearance() {
        let deleted = directory.appending(path: "已删除", directoryHint: .isDirectory)

        #expect(FinderFolderAppearance(folderAt: deleted) == FinderFolderAppearance(
            tagColor: nil,
            symbolOrEmoji: nil,
            hasCustomIcon: false
        ))
    }
}

// MARK: - Private

extension FinderFolderAppearanceTests {
    /// 在临时目录里新建一个文件夹并打上标签
    /// - Parameter tags: 标签，每项是 “名称\n颜色号”；为空时不打
    private func makeFolder(tags: [String]) throws -> URL {
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FinderFolderAttributes.setTags(tags, of: folder)

        return folder
    }
}
