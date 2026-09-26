import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderIconRendererTests

/// 文件夹图标渲染（需求 2）：预览网格的几何，以及不同预览数量下的输出
///
/// 放在主线程串行执行：并发栅格化同一个 App 图标时，偶尔会画出不同的像素
@MainActor
struct FolderIconRendererTests {
    /// 用作预览的四个系统 App，图标各不相同
    private let appURLs = ["Calculator", "Calendar", "Chess", "Dictionary"].map {
        URL(filePath: "/System/Applications/\($0).app")
    }

    /// 单元格按左上、右上、左下、右下排列，边长 0.23、间距 0.04，外框为 x ∈ [0.25, 0.75]、y ∈ [0.36, 0.86]
    @Test
    func previewCellsFollowGridGeometry() {
        let canvas = CGRect(x: 0, y: 0, width: 100, height: 100)
        let frames = (0 ..< 4).map {
            FolderIconRenderer.previewCellFrame(at: $0, in: canvas)
        }

        let expected = [
            CGRect(x: 25, y: 36, width: 23, height: 23),
            CGRect(x: 52, y: 36, width: 23, height: 23),
            CGRect(x: 25, y: 63, width: 23, height: 23),
            CGRect(x: 52, y: 63, width: 23, height: 23),
        ]

        for (frame, expectedFrame) in zip(frames, expected) {
            #expect(isClose(frame, expectedFrame))
        }
    }

    /// 非正方形的图标等比缩放后在单元格内居中
    @Test
    func aspectFitCentersContent() {
        let cell = CGRect(x: 10, y: 10, width: 20, height: 20)
        let fitted = FolderIconRenderer.aspectFitFrame(
            for: CGSize(width: 40, height: 20),
            in: cell
        )

        #expect(isClose(fitted, CGRect(x: 10, y: 15, width: 20, height: 10)))
    }

    /// 输出图像的点尺寸等于请求的边长
    @Test(arguments: [16, 64, 512] as [CGFloat])
    func outputMatchesPointSize(pointSize: CGFloat) {
        let image = FolderIconRenderer.render(
            folder: makeFolder(appCount: 4),
            previewIconCount: 4,
            pointSize: pointSize
        )

        #expect(image.size == NSSize(width: pointSize, height: pointSize))
    }

    /// 预览数量从 0 到 4 递增时，每多一个预览，画面都会变化
    @Test
    func everyPreviewCountRendersDistinctly() throws {
        let folder = makeFolder(appCount: 4)
        let bitmaps = try (0 ... 4).map {
            try renderedPixels(of: folder, previewIconCount: $0)
        }

        for index in 1 ..< bitmaps.count {
            #expect(bitmaps[index] != bitmaps[index - 1])
        }
    }

    /// 预览数量超过 App 数量时只画已有的 App，不崩溃
    @Test
    func previewCountBeyondAppCountDrawsAvailableApps() throws {
        let folder = makeFolder(appCount: 2)

        let requestedFour = try renderedPixels(of: folder, previewIconCount: 4)
        let requestedTwo = try renderedPixels(of: folder, previewIconCount: 2)

        #expect(requestedFour == requestedTwo)
    }

    /// 子文件夹不参与预览，跳过它继续取后面的 App
    @Test
    func subfoldersAreSkipped() throws {
        let apps = makeFolder(appCount: 1).items
        let withSubfolder = Folder(
            id: UUID(),
            name: "混排",
            items: [.folder(Folder(id: UUID(), name: "子文件夹", items: []))] + apps
        )

        let appsOnly = Folder(id: UUID(), name: "仅 App", items: apps)

        let mixed = try renderedPixels(of: withSubfolder, previewIconCount: 1)
        let plain = try renderedPixels(of: appsOnly, previewIconCount: 1)

        #expect(mixed == plain)
    }

    /// 构造包含前 appCount 个系统 App 的文件夹
    private func makeFolder(appCount: Int) -> Folder {
        Folder(
            id: UUID(),
            name: "测试",
            items: appURLs.prefix(appCount).map {
                .app(AppReference(id: UUID(), url: $0))
            }
        )
    }

    /// 两个矩形在浮点误差内相等
    private func isClose(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance = 1e-9

        return abs(lhs.minX - rhs.minX) < tolerance
            && abs(lhs.minY - rhs.minY) < tolerance
            && abs(lhs.width - rhs.width) < tolerance
            && abs(lhs.height - rhs.height) < tolerance
    }

    /// 以 64 点渲染文件夹图标，再按 2 倍像素栅格化，返回像素数据用于比较
    private func renderedPixels(
        of folder: Folder,
        previewIconCount: Int
    ) throws -> Data {
        let image = FolderIconRenderer.render(
            folder: folder,
            previewIconCount: previewIconCount,
            pointSize: 64
        )

        let pixelSide = Int(image.size.width) * 2
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelSide,
                pixelsHigh: pixelSide,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        bitmap.size = image.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        return try #require(bitmap.tiffRepresentation)
    }
}
