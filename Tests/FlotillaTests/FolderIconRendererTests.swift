import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderIconRendererTests

/// 文件夹图标渲染（需求 2）：底板的形状、预览网格的几何、不同预览数量下的输出，以及深浅两种外观的底板
///
/// 放在主线程串行执行：并发栅格化同一个 App 图标时，偶尔会画出不同的像素
@MainActor
struct FolderIconRendererTests {
    /// 用作预览的四个系统 App，图标各不相同
    private let appURLs = ["Calculator", "Calendar", "Chess", "Dictionary"].map {
        URL(filePath: "/System/Applications/\($0).app")
    }

    /// 单元格按左上、右上、左下、右下排列：边长 0.35，左上格原点 (0.152, 0.152)，格距 0.346
    @Test
    func previewCellsFollowGridGeometry() {
        let canvas = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let frames = (0 ..< 4).map {
            FolderIconRenderer.previewCellFrame(at: $0, in: canvas)
        }

        let expected = [
            CGRect(x: 152, y: 152, width: 350, height: 350),
            CGRect(x: 498, y: 152, width: 350, height: 350),
            CGRect(x: 152, y: 498, width: 350, height: 350),
            CGRect(x: 498, y: 498, width: 350, height: 350),
        ]

        for (frame, expectedFrame) in zip(frames, expected) {
            #expect(isClose(frame, expectedFrame))
        }
    }

    /// App 图标四边各有 100/1024 的透明边；扣掉之后，四个预览的可见底板合起来在画布上居中，
    /// 范围约为 [0.186, 0.814]，相邻两个之间约隔 0.064，整体落在文件夹底板 [100/1024, 924/1024] 之内
    @Test
    func visiblePreviewPlatesAreCentered() {
        let canvas = CGRect(x: 0, y: 0, width: 1, height: 1)
        let visiblePlates = (0 ..< 4).map {
            let cell = FolderIconRenderer.previewCellFrame(at: $0, in: canvas)
            let margin = cell.width * 100 / 1024

            return cell.insetBy(dx: margin, dy: margin)
        }

        let union = visiblePlates.reduce(CGRect.null) { $0.union($1) }
        let gap = visiblePlates[1].minX - visiblePlates[0].maxX

        #expect(abs(union.midX - 0.5) < 1e-9)
        #expect(abs(union.midY - 0.5) < 1e-9)
        #expect(abs(union.minX - 0.186) < 0.001)
        #expect(abs(union.maxX - 0.814) < 0.001)
        #expect(abs(gap - 0.064) < 0.001)
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
    @Test(
        arguments: [16, 64, 512, 1024] as [CGFloat],
        [FolderIconAppearance.dark, .light]
    )
    func outputMatchesPointSize(pointSize: CGFloat, appearance: FolderIconAppearance) {
        let image = FolderIconRenderer.render(
            folder: makeFolder(appCount: 4),
            previewIconCount: 4,
            pointSize: pointSize,
            appearance: appearance
        )

        #expect(image.size == NSSize(width: pointSize, height: pointSize))
    }

    /// 预览数量从 0 到 4 递增时，每多一个预览，画面都会变化
    @Test(arguments: [FolderIconAppearance.dark, .light])
    func everyPreviewCountRendersDistinctly(appearance: FolderIconAppearance) throws {
        let folder = makeFolder(appCount: 4)
        let bitmaps = try (0 ... 4).map {
            try renderedPixels(
                of: folder,
                previewIconCount: $0,
                appearance: appearance
            )
        }

        for index in 1 ..< bitmaps.count {
            #expect(bitmaps[index] != bitmaps[index - 1])
        }
    }

    /// 预览数量超过 App 数量时只画已有的 App，不崩溃
    @Test(arguments: [FolderIconAppearance.dark, .light])
    func previewCountBeyondAppCountDrawsAvailableApps(appearance: FolderIconAppearance) throws {
        let folder = makeFolder(appCount: 2)

        let requestedFour = try renderedPixels(
            of: folder,
            previewIconCount: 4,
            appearance: appearance
        )

        let requestedTwo = try renderedPixels(
            of: folder,
            previewIconCount: 2,
            appearance: appearance
        )

        #expect(requestedFour == requestedTwo)
    }

    /// 子文件夹不参与预览，跳过它继续取后面的 App
    @Test(arguments: [FolderIconAppearance.dark, .light])
    func subfoldersAreSkipped(appearance: FolderIconAppearance) throws {
        let apps = makeFolder(appCount: 1).items
        let withSubfolder = Folder(
            id: UUID(),
            name: "混排",
            items: [.folder(Folder(id: UUID(), name: "子文件夹", items: []))] + apps
        )

        let appsOnly = Folder(id: UUID(), name: "仅 App", items: apps)

        let mixed = try renderedPixels(
            of: withSubfolder,
            previewIconCount: 1,
            appearance: appearance
        )

        let plain = try renderedPixels(
            of: appsOnly,
            previewIconCount: 1,
            appearance: appearance
        )

        #expect(mixed == plain)
    }

    /// 预览数量为 0 与文件夹里没有 App 时都只画底板，两者画面相同
    @Test(arguments: [FolderIconAppearance.dark, .light])
    func emptyPreviewDrawsPlateOnly(appearance: FolderIconAppearance) throws {
        let countZero = try renderedPixels(
            of: makeFolder(appCount: 4),
            previewIconCount: 0,
            appearance: appearance
        )

        let noApps = try renderedPixels(
            of: makeFolder(appCount: 0),
            previewIconCount: 4,
            appearance: appearance
        )

        #expect(countZero == noApps)
    }

    /// 底板与系统 App 图标的底板重合：按 1024 像素栅格化后，不透明部分的包围盒是 [100, 923]
    @Test(arguments: [FolderIconAppearance.dark, .light])
    func plateMatchesSystemIconPlate(appearance: FolderIconAppearance) throws {
        let bitmap = try rasterizedPlate(appearance: appearance)
        var bounds = (minX: Int.max, maxX: Int.min, minY: Int.max, maxY: Int.min)

        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide where alpha(of: bitmap, x: x, y: y) > 128 {
                bounds.minX = min(bounds.minX, x)
                bounds.maxX = max(bounds.maxX, x)
                bounds.minY = min(bounds.minY, y)
                bounds.maxY = max(bounds.maxY, y)
            }
        }

        #expect(bounds.minX == 100)
        #expect(bounds.maxX == 923)
        #expect(bounds.minY == 100)
        #expect(bounds.maxY == 923)
    }

    /// 底板是圆角方形：包围盒的四个角外侧，沿对角线往里 40 像素以内都是透明的
    @Test(arguments: [FolderIconAppearance.dark, .light])
    func plateCornersAreTransparent(appearance: FolderIconAppearance) throws {
        let bitmap = try rasterizedPlate(appearance: appearance)

        // 每个角是（角点、沿对角线往里的方向）
        let corners = [
            (100, 100, 1, 1),
            (923, 100, -1, 1),
            (100, 923, 1, -1),
            (923, 923, -1, -1),
        ]

        for (cornerX, cornerY, stepX, stepY) in corners {
            for distance in 0 ... 40 {
                let x = cornerX + stepX * distance
                let y = cornerY + stepY * distance

                #expect(alpha(of: bitmap, x: x, y: y) == 0)
            }
        }
    }

    /// 深浅两种外观只换颜色：透明与不透明的像素分布逐像素相同，Dock 上的轮廓不随外观变化
    @Test
    func plateShapeIsSameInBothAppearances() throws {
        let dark = try rasterizedPlate(appearance: .dark)
        let light = try rasterizedPlate(appearance: .light)

        var mismatchCount = 0

        for y in 0 ..< dark.pixelsHigh {
            for x in 0 ..< dark.pixelsWide {
                let isDarkTransparent = alpha(of: dark, x: x, y: y) == 0
                let isLightTransparent = alpha(of: light, x: x, y: y) == 0

                if isDarkTransparent != isLightTransparent {
                    mismatchCount += 1
                }
            }
        }

        #expect(mismatchCount == 0)
    }

    /// 底板随外观分深浅：深色外观下中线自上而下都比中灰暗，不会在深色 Dock 上亮成一块；
    /// 浅色外观下都比中灰亮。两种外观都是上亮下暗的渐变
    @Test(arguments: [FolderIconAppearance.dark, .light])
    func plateBrightnessFollowsAppearance(appearance: FolderIconAppearance) throws {
        let bitmap = try rasterizedPlate(appearance: appearance)

        // 中线上避开边线的上、中、下三处
        let grays = [150, 512, 870].map {
            gray(of: bitmap, x: 512, y: $0)
        }

        switch appearance {
        case .dark:
            #expect(grays.allSatisfy { $0 < 128 })

        case .light:
            #expect(grays.allSatisfy { $0 > 128 })
        }

        #expect(grays[0] > grays[1])
        #expect(grays[1] > grays[2])
    }

    /// 边线要与底板区分开，底板与背景颜色相近时轮廓仍然可辨：
    /// 深色底板上是比内部亮的亮线，浅色底板上是比内部暗的暗线
    @Test(arguments: [FolderIconAppearance.dark, .light])
    func plateEdgeContrastsWithInterior(appearance: FolderIconAppearance) throws {
        let bitmap = try rasterizedPlate(appearance: appearance)

        // 左边的中点：边线紧贴轮廓内侧，宽 4.5 像素，x 101 落在边线上，x 110 已在底板内部
        let edge = gray(of: bitmap, x: 101, y: 512)
        let interior = gray(of: bitmap, x: 110, y: 512)

        switch appearance {
        case .dark:
            #expect(edge > interior)

        case .light:
            #expect(edge < interior)
        }
    }
}

// MARK: - Private

extension FolderIconRendererTests {
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
        previewIconCount: Int,
        appearance: FolderIconAppearance
    ) throws -> Data {
        let image = FolderIconRenderer.render(
            folder: folder,
            previewIconCount: previewIconCount,
            pointSize: 64,
            appearance: appearance
        )

        let bitmap = try rasterize(image, pixelSide: 128)

        return try #require(bitmap.tiffRepresentation)
    }

    /// 只有底板的文件夹图标，以 1024 点渲染、按 1024 像素栅格化
    private func rasterizedPlate(appearance: FolderIconAppearance) throws -> NSBitmapImageRep {
        let image = FolderIconRenderer.render(
            folder: makeFolder(appCount: 0),
            previewIconCount: 0,
            pointSize: 1024,
            appearance: appearance
        )

        return try rasterize(image, pixelSide: 1024)
    }

    /// 把图像栅格化为边长 pixelSide 像素的位图
    private func rasterize(_ image: NSImage, pixelSide: Int) throws -> NSBitmapImageRep {
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

        return bitmap
    }

    /// 位图上一个像素的不透明度，0–255；y 轴自上而下
    private func alpha(of bitmap: NSBitmapImageRep, x: Int, y: Int) -> Int {
        var pixel = [Int](repeating: 0, count: 4)
        bitmap.getPixel(&pixel, atX: x, y: y)

        return pixel[3]
    }

    /// 位图上一个像素去掉预乘后的灰度，0–255，取红色分量；全透明时为 0，y 轴自上而下
    private func gray(of bitmap: NSBitmapImageRep, x: Int, y: Int) -> Double {
        var pixel = [Int](repeating: 0, count: 4)
        bitmap.getPixel(&pixel, atX: x, y: y)

        guard pixel[3] > 0 else { return 0 }

        return Double(pixel[0]) * 255 / Double(pixel[3])
    }
}
