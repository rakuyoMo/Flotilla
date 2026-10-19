import AppKit
import QuickLookThumbnailing
import Testing

@testable import Flotilla

// MARK: - FileThumbnailLoaderTests

/// 访达文件夹的层级里上了色的子文件夹：显示 QuickLook 画好的文件夹图标，画满 101 pt 的图标画布，
/// 与其它格的图标一样大，不像内容缩略图那样缩进 100 pt 的画布
@MainActor
final class FileThumbnailLoaderTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 2 倍屏上，加载器给的图标与 QuickLook 按 101 pt、2 倍给的图标画满同一块画布，逐像素相同
    @Test
    func folderIconFillsIconCanvas() async throws {
        let folder = directory.appending(path: "红色", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FinderFolderAttributes.setTags(["红色\n6"], of: folder)

        let loader = FileThumbnailLoader(scale: 2)
        var loadedIcon: NSImage? = nil

        _ = loader.loadThumbnail(of: folder, representation: .icon) {
            loadedIcon = $0
        }

        // 500 轮总共至少 10 s：CI 上 QuickLook 冷启动也要等得及
        await Polling.wait(rounds: 500) { loadedIcon != nil }

        let icon = try #require(loadedIcon)
        let side = GroupPanelMetrics.iconSize
        let expected = try await quickLookIcon(of: folder, side: side, scale: 2)

        #expect(icon.size == CGSize(width: side, height: side))

        #expect(
            try IconPixels.pixels(of: icon, side: side, scale: 2)
                == IconPixels.pixels(of: expected, side: side, scale: 2)
        )
    }
}

// MARK: - Private

extension FileThumbnailLoaderTests {
    /// 直接向 QuickLook 取文件夹的 `.icon`，画满边长 side 的画布
    /// - Parameters:
    ///   - folder: 文件夹的 URL
    ///   - side: 请求与画布的边长（pt）
    ///   - scale: 屏幕倍率
    private func quickLookIcon(
        of folder: URL,
        side: CGFloat,
        scale: CGFloat
    ) async throws -> NSImage {
        let request = QLThumbnailGenerator.Request(
            fileAt: folder,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .icon
        )

        let bitmap = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.cgImage)
            }
        }

        return NSImage(
            cgImage: try #require(bitmap),
            size: CGSize(width: side, height: side)
        )
    }
}
