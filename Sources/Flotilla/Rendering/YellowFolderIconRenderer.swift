import AppKit
import UniformTypeIdentifiers

// MARK: - YellowFolderIconRenderer

/// 设置窗口里组这一行的黄色文件夹图标（需求 35）：系统的通用文件夹图标按亮度换成系统黄色标签的颜色，透明度不变
///
/// 色阶照 QuickLook 按 `.icon` 给打了黄色标签的访达文件夹画出的图标拟合；
/// 实测（macOS 27）`NSWorkspace` 给这样的文件夹仍是蓝色图标，取不到系统的黄色文件夹
enum YellowFolderIconRenderer {
    /// 亮度 → 颜色的色阶，都是 0–255 的 sRGB 编码值；相邻两档之间按亮度线性插值，最亮一档之上取它的颜色
    ///
    /// 亮度 0 是黑色：文件夹下方的阴影是黑色，系统的黄色文件夹里同样是黑色
    private static let stops: [(luminance: Double, red: Double, green: Double, blue: Double)] = [
        (0, 0, 0, 0),
        (179, 253, 202, 0),
        (190, 255, 210, 89),
    ]

    /// 边长 pointSize 点的黄色文件夹图标
    ///
    /// 带 1 倍、2 倍屏各一张位图：显示时取像素尺寸与屏幕相符的那张，不再缩放，两种屏幕上都清楚
    /// - Parameter pointSize: 图标的边长（pt）
    @MainActor
    static func render(pointSize: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))

        for scale: CGFloat in [1, 2] {
            guard let bitmap = renderBitmap(pointSize: pointSize, scale: scale) else { continue }

            // 位图的点尺寸设成图标尺寸，像素数与点数之比就是它对应的屏幕倍率
            let representation = NSBitmapImageRep(cgImage: bitmap)
            representation.size = image.size

            image.addRepresentation(representation)
        }

        return image
    }
}

// MARK: - Private

extension YellowFolderIconRenderer {
    /// 把系统的通用文件夹图标按边长 pointSize 点、scale 倍栅格化，再逐像素换成黄色
    /// - Parameters:
    ///   - pointSize: 图标的边长（pt）
    ///   - scale: 屏幕倍率
    /// - Returns: 边长 pointSize × scale 像素的图标；建不起位图上下文时为 nil
    @MainActor
    private static func renderBitmap(
        pointSize: CGFloat,
        scale: CGFloat
    ) -> CGImage? {
        let pixelSide = Int((pointSize * scale).rounded())

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: pixelSide,
                height: pixelSide,
                bitsPerComponent: 8,
                bytesPerRow: pixelSide * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        // 按点绘制、按倍率换算像素：系统按这个倍率挑选图标的位图，画出的与图标直接显示在这种屏幕上相同
        context.scaleBy(x: scale, y: scale)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        NSWorkspace.shared.icon(for: .folder).draw(
            in: NSRect(x: 0, y: 0, width: pointSize, height: pointSize)
        )

        NSGraphicsContext.restoreGraphicsState()

        recolorPixels(in: context)

        return context.makeImage()
    }

    /// 把位图上每个像素的颜色换成它的亮度在色阶上对应的颜色，透明度不变
    /// - Parameter context: 8 位 RGBA、预乘透明度的 sRGB 位图上下文
    private static func recolorPixels(in context: CGContext) {
        guard let data = context.data else { return }

        let pixelCount = context.width * context.height
        let pixels = data.bindMemory(to: UInt8.self, capacity: pixelCount * 4)

        for index in 0 ..< pixelCount {
            let base = index * 4
            let alpha = Double(pixels[base + 3]) / 255

            // 全透明的像素（图标四周的透明边）没有颜色可换
            guard alpha > 0 else { continue }

            // 位图预乘了透明度，除掉透明度还原出真实颜色，再按 Rec. 709 系数算亮度，范围 0–255
            let luminance = (
                0.2126 * Double(pixels[base])
                    + 0.7152 * Double(pixels[base + 1])
                    + 0.0722 * Double(pixels[base + 2])
            ) / alpha

            let color = color(atLuminance: luminance)

            // 写回时重新乘上透明度，透明度本身不变
            pixels[base] = premultipliedByte(color.red, alpha: alpha)
            pixels[base + 1] = premultipliedByte(color.green, alpha: alpha)
            pixels[base + 2] = premultipliedByte(color.blue, alpha: alpha)
        }
    }

    /// 亮度在色阶上对应的颜色：落在两档之间时按亮度线性插值，最亮一档之上取它的颜色
    /// - Parameter luminance: 未预乘的亮度，0–255
    /// - Returns: 0–255 的 sRGB 编码值
    private static func color(
        atLuminance luminance: Double
    ) -> (red: Double, green: Double, blue: Double) {
        guard let upperIndex = stops.firstIndex(where: { $0.luminance >= luminance }) else {
            let brightest = stops[stops.count - 1]

            return (brightest.red, brightest.green, brightest.blue)
        }

        let upper = stops[upperIndex]

        // 亮度恰好是最暗一档
        guard upperIndex > 0 else {
            return (upper.red, upper.green, upper.blue)
        }

        let lower = stops[upperIndex - 1]
        let fraction = (luminance - lower.luminance) / (upper.luminance - lower.luminance)

        return (
            red: lower.red + (upper.red - lower.red) * fraction,
            green: lower.green + (upper.green - lower.green) * fraction,
            blue: lower.blue + (upper.blue - lower.blue) * fraction
        )
    }

    /// 把 0–255 的通道值夹进范围、乘上透明度，取整成 8 位整数
    /// - Parameters:
    ///   - value: 未预乘的通道值，0–255
    ///   - alpha: 像素的透明度，0–1
    private static func premultipliedByte(
        _ value: Double,
        alpha: Double
    ) -> UInt8 {
        UInt8((min(max(value, 0), 255) * alpha).rounded())
    }
}
