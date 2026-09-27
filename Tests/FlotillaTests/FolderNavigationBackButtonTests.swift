import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderNavigationBackButtonTests

/// 返回按钮画出的范围与原生实测一致：深色底色不占满 21 × 22 pt 的 frame，chevron 在两种外观下位置与大小相同
///
/// 坐标都是 2 倍像素，原点在按钮 frame 左上角、y 向下，与原生截图的读法相同
@MainActor
struct FolderNavigationBackButtonTests {
    /// 底色范围：深色 21 × 21 pt 贴 frame 顶边、最下面 1 pt 什么都不画；浅色不透明的底色 19 × 19 pt，四周各让出 1 pt 给暗线与投影
    @Test(arguments: [
        (NSAppearance.Name.darkAqua, 0 ... 41, 0 ... 41),
        (.aqua, 2 ... 39, 2 ... 39),
    ])
    func bezelCoversMeasuredArea(
        appearance: NSAppearance.Name,
        expectedX: ClosedRange<Int>,
        expectedY: ClosedRange<Int>
    ) throws {
        let bitmap = try render(in: appearance)

        // 深色底色半透明，凡是画过的像素都算；浅色只看不透明的底色，暗线与投影不算
        let threshold = appearance == .darkAqua ? 0 : 254
        let box = try #require(boundingBox(of: bitmap) { $0[3] > threshold })

        #expect(box.x == expectedX)
        #expect(box.y == expectedY)
    }

    /// chevron 范围：覆盖率超过 1/4 的像素在两种外观下都是 x 13…25、y 10…31，与原生深色、浅色的读数相同
    @Test(arguments: [NSAppearance.Name.darkAqua, .aqua])
    func chevronCoversMeasuredArea(appearance: NSAppearance.Name) throws {
        let bitmap = try render(in: appearance)
        let isDark = appearance == .darkAqua

        // 深色的 chevron 是叠在半透明白色底色上的不透明白色，看不透明度；浅色是叠在白色底色上的黑色，看灰度
        let channel = isDark ? 3 : 1
        let bezel = pixel(of: bitmap, x: 36, y: 20)[channel]
        let ink = isDark
            ? 255
            : Int(255 * (1 - FolderPanelAppearance.light.backButtonChevronColor.alphaComponent))

        let box = try #require(boundingBox(of: bitmap) {
            let coverage = Double($0[channel] - bezel) / Double(ink - bezel)

            // 浅色底色之外是透明像素，不参与判断
            return (isDark || $0[3] == 255) && coverage > 0.25
        })

        #expect(box.x == 13 ... 25)
        #expect(box.y == 10 ... 31)
    }
}

// MARK: - Private

extension FolderNavigationBackButtonTests {
    /// 在指定外观下把按钮画到透明背景上，返回 2 倍像素的位图
    private func render(in name: NSAppearance.Name) throws -> NSBitmapImageRep {
        let button = FolderNavigationBackButton { }
        button.frame = CGRect(origin: .zero, size: FolderPanelMetrics.backButtonFrame.size)
        button.appearance = NSAppearance(named: name)

        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(button.bounds.width * 2),
                pixelsHigh: Int(button.bounds.height * 2),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        // 位图的点尺寸等于按钮尺寸，AppKit 按 2 倍换算
        bitmap.size = button.bounds.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            button.draw(button.bounds)
        }

        NSGraphicsContext.restoreGraphicsState()

        return bitmap
    }

    /// 满足条件的像素的包围盒；没有这样的像素时为 nil
    /// - Parameters:
    ///   - bitmap: 要检查的位图
    ///   - predicate: 判断一个像素的 RGBA 分量（0–255）
    private func boundingBox(
        of bitmap: NSBitmapImageRep,
        where predicate: ([Int]) -> Bool
    ) -> (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
        var minX = Int.max
        var maxX = Int.min
        var minY = Int.max
        var maxY = Int.min

        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide where predicate(pixel(of: bitmap, x: x, y: y)) {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        guard minX <= maxX else { return nil }

        return (minX ... maxX, minY ... maxY)
    }

    /// 位图上一个像素的 RGBA 分量，0–255；y 轴自上而下
    private func pixel(of bitmap: NSBitmapImageRep, x: Int, y: Int) -> [Int] {
        var pixel = [Int](repeating: 0, count: 4)
        bitmap.getPixel(&pixel, atX: x, y: y)

        return pixel
    }
}
