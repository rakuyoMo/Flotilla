import AppKit
import Testing

@testable import Flotilla

// MARK: - StatusBarIconTests

/// 状态栏图标（需求 7）：由系统按菜单栏深浅着色、在状态栏按钮里居中，1 倍屏上直线边缘不发虚，旁白读出当前语言下的 App 名
struct StatusBarIconTests {
    /// 必须是 template 图：否则深色菜单栏上仍画成黑色，看不见
    @Test
    func imageIsTemplate() {
        #expect(StatusBarIcon.makeImage().isTemplate)
    }

    /// 无障碍描述是这种语言下的 App 名：旁白读出的名字与访达、Dock 里显示的一致
    @Test(arguments: LocalizationTests.languages)
    func accessibilityDescriptionIsAppName(language: String) throws {
        let key = try #require(StatusBarIcon.makeImage().accessibilityDescription)

        // 测试进程读不到 `.lproj` 里的译文，无障碍描述就是键名，按键名查这种语言的文字
        let description = try LocalizationTests.table(for: language)[key]

        #expect(description == LocalizedAppNameTests.appNames[language])
    }

    /// 画布 16 pt 见方，船从画布顶端画到底端，左右各空 1 pt：放进 22 pt 的按钮后上下左右都居中
    @Test
    func figureFillsHeightAndIsCentered() throws {
        let image = StatusBarIcon.makeImage()
        let bitmap = try rasterize(image, scale: 2)
        let ink = inkBounds(of: bitmap)

        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(ink.minY == 0)
        #expect(ink.maxY == 31)
        #expect(ink.minX == 2)
        #expect(ink.maxX == 29)
    }

    /// 1 倍下桅杆占满 x = 6 这一列、甲板占满 y = 13 这一行、船底占满 y = 15 这一行，旁边的像素全透明
    @Test
    func straightEdgesAlignToPixelsAt1x() throws {
        let bitmap = try rasterize(StatusBarIcon.makeImage(), scale: 1)

        // 下帆与甲板之间那一行只有桅杆，桅杆左右两列全透明
        #expect(alpha(of: bitmap, x: 6, y: 12) == 255)
        #expect(alpha(of: bitmap, x: 5, y: 12) == 0)
        #expect(alpha(of: bitmap, x: 7, y: 12) == 0)

        // 甲板以上一行透明，甲板这一行与船底这一行不透明
        for x in 3 ... 9 where x != 6 {
            #expect(alpha(of: bitmap, x: x, y: 12) == 0)
            #expect(alpha(of: bitmap, x: x, y: 13) == 255)
        }

        for x in 4 ... 8 {
            #expect(alpha(of: bitmap, x: x, y: 15) == 255)
        }
    }
}

// MARK: - Private

extension StatusBarIconTests {
    /// 按 `scale` 倍像素栅格化图像
    private func rasterize(_ image: NSImage, scale: Int) throws -> NSBitmapImageRep {
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(image.size.width) * scale,
                pixelsHigh: Int(image.size.height) * scale,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        // 位图的点尺寸设成图像尺寸，绘制时按像素数与点数之比换算倍率
        bitmap.size = image.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }

    /// 所有画过的像素（不透明度大于 0）的包围盒，以像素为单位，y 轴自上而下
    private func inkBounds(of bitmap: NSBitmapImageRep) -> (
        minX: Int,
        maxX: Int,
        minY: Int,
        maxY: Int
    ) {
        var bounds = (minX: Int.max, maxX: Int.min, minY: Int.max, maxY: Int.min)

        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide where alpha(of: bitmap, x: x, y: y) > 0 {
                bounds.minX = min(bounds.minX, x)
                bounds.maxX = max(bounds.maxX, x)
                bounds.minY = min(bounds.minY, y)
                bounds.maxY = max(bounds.maxY, y)
            }
        }

        return bounds
    }

    /// 位图上一个像素的不透明度，0–255；y 轴自上而下
    private func alpha(of bitmap: NSBitmapImageRep, x: Int, y: Int) -> Int {
        var pixel = [Int](repeating: 0, count: 4)
        bitmap.getPixel(&pixel, atX: x, y: y)

        return pixel[3]
    }
}
