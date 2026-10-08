import AppKit
import Testing
import UniformTypeIdentifiers

@testable import Flotilla

// MARK: - FileReferenceIconTests

/// 文件的图标与访达一致：`icon(forFile:)` 把名称开头的 “.” 后面当成扩展名，`.a` 画成归档、`.zip` 画成压缩包；
/// 名称以 “.” 开头、没有扩展名的文件与文件夹按内容类型取，其余的项按文件取，自定义图标与替身箭头才显示得出
///
/// 放在主线程串行执行：并发栅格化同一个图标时，偶尔会画出不同的像素
@MainActor
final class FileReferenceIconTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 建好临时目录
    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// `.a`、`.zip` 这类名称的文件类型是 `public.data`：图标与按这个类型取的相同，访达里同样是通用文稿
    @Test(arguments: [".a", ".zip"])
    func dotNamedFileUsesContentTypeIcon(name: String) throws {
        let url = try writeFile(name)

        let expected = try pixels(of: NSWorkspace.shared.icon(for: .data))

        #expect(try pixels(of: icon(of: url)) == expected)
    }

    /// 名称以 “.” 开头、没有扩展名的目录是普通文件夹：图标与按文件夹类型取的相同，不是 bundle 的图标
    @Test
    func dotNamedFolderUsesFolderIcon() throws {
        let url = directory.appending(path: ".bundle", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let expected = try pixels(of: NSWorkspace.shared.icon(for: .folder))

        #expect(try pixels(of: icon(of: url)) == expected)
    }

    /// 有扩展名的隐藏文件、名称不以 “.” 开头的文件按文件取：粘贴过的自定义图标照样显示
    @Test(arguments: [".甲.txt", "n"])
    func otherFilesKeepCustomIcon(name: String) throws {
        let url = try writeFile(name)
        try setCustomIcon(on: url)

        let expected = try pixels(of: fileIcon(of: url))

        #expect(try pixels(of: icon(of: url)) == expected)
    }

    /// 名称以 “.” 开头的符号链接按文件取：图标是目标的图标加替身箭头
    @Test
    func symbolicLinkKeepsAliasBadge() throws {
        let target = try writeFile("n")
        let link = directory.appending(path: ".链接")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let expected = try pixels(of: fileIcon(of: link))

        #expect(try pixels(of: icon(of: link)) == expected)
    }

    /// 名称以 “.” 开头、没有扩展名的文件包按文件取：按类型取会是带 “?” 的文稿
    @Test
    func dotNamedPackageKeepsFileIcon() throws {
        let url = directory.appending(path: ".包", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try setBundleBit(on: url)

        try #require(url.resourceValues(forKeys: [.isPackageKey]).isPackage ?? false)

        let expected = try pixels(of: fileIcon(of: url))

        #expect(try pixels(of: icon(of: url)) == expected)
    }
}

// MARK: - Private

extension FileReferenceIconTests {
    /// 指向这个位置的文件引用给出的图标
    private func icon(of url: URL) -> NSImage {
        FileReference(id: UUID(), url: url, bookmark: nil).icon
    }

    /// `icon(forFile:)` 给出的图标
    private func fileIcon(of url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }

    /// 在临时目录里写一个文件，返回它的 URL
    private func writeFile(_ name: String) throws -> URL {
        let url = directory.appending(path: name)
        try Data(name.utf8).write(to: url)

        return url
    }

    /// 给文件粘贴一个纯红的自定义图标，与系统给任何类型的图标都不同
    private func setCustomIcon(on url: URL) throws {
        let image = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect -> Bool in
            NSColor.systemRed.setFill()
            rect.fill()

            return true
        }

        try #require(NSWorkspace.shared.setIcon(image, forFile: url.path(percentEncoded: false)))
    }

    /// 给目录设上 bundle 标志（Finder 信息的标志位 `0x2000`），系统据此把它当成文件包
    private func setBundleBit(on url: URL) throws {
        var finderInfo = [UInt8](repeating: 0, count: 32)
        finderInfo[8] = 0x20

        let result = url.withUnsafeFileSystemRepresentation {
            setxattr($0, "com.apple.FinderInfo", finderInfo, finderInfo.count, 0, 0)
        }

        try #require(result == 0)
    }

    /// 把图标按 32 pt、2 倍栅格化，返回像素数据用于逐字节比较
    private func pixels(of image: NSImage) throws -> Data {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 64,
                pixelsHigh: 64,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        bitmap.size = NSSize(width: 32, height: 32)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: bitmap.size))
        NSGraphicsContext.restoreGraphicsState()

        return try #require(bitmap.tiffRepresentation)
    }
}
