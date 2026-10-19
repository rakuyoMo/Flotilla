import AppKit
import Testing

// MARK: - IconPixels

/// 测试里读图标的像素：按给定的边长与倍率画进 8 位 RGBA、预乘透明度的 sRGB 位图，与图标显示在这种屏幕上相同
enum IconPixels {
    /// 图标画出来的全部字节，自上而下逐行排列
    /// - Parameters:
    ///   - image: 图标
    ///   - side: 绘制的边长（pt）
    ///   - scale: 屏幕倍率
    @MainActor
    static func pixels(of image: NSImage, side: CGFloat, scale: CGFloat) throws -> [UInt8] {
        let pixelSide = Int((side * scale).rounded())
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))

        let context = try #require(
            CGContext(
                data: nil,
                width: pixelSide,
                height: pixelSide,
                bitsPerComponent: 8,
                bytesPerRow: pixelSide * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )

        // 按点绘制、按倍率换算像素：系统按这个倍率挑选图标的位图
        context.scaleBy(x: scale, y: scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))

        NSGraphicsContext.restoreGraphicsState()

        let data = try #require(context.data)
            .bindMemory(to: UInt8.self, capacity: pixelSide * pixelSide * 4)

        return Array(UnsafeBufferPointer(start: data, count: pixelSide * pixelSide * 4))
    }

    /// 图标正中那个像素的红、绿、蓝，0–255；文件夹图标的正中落在文件夹正面上
    /// - Parameters:
    ///   - image: 图标
    ///   - side: 绘制的边长（pt）
    ///   - scale: 屏幕倍率
    @MainActor
    static func centerColor(
        of image: NSImage,
        side: CGFloat,
        scale: CGFloat
    ) throws -> (red: Int, green: Int, blue: Int) {
        let pixels = try pixels(of: image, side: side, scale: scale)
        let pixelSide = Int((side * scale).rounded())
        let base = (pixelSide / 2 * pixelSide + pixelSide / 2) * 4

        return (Int(pixels[base]), Int(pixels[base + 1]), Int(pixels[base + 2]))
    }
}
