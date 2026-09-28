import AppKit

// MARK: - DarkIconStyleRenderer

/// 按系统对 App 图标的“透明 · 深色”“色调 · 深色”处理，给一张图标重新上色
///
/// 两种处理都只看像素的 Rec. 709 亮度（在 sRGB 编码值上计算），输出是亮度的线性函数，透明度不变；
/// 系数按 macOS 27 的 Dock 对包内图标的处理效果拟合
enum DarkIconStyleRenderer {
    /// 透明 · 深色：亮度为 0 时的灰度
    private static let clearOffset = 0.075

    /// 透明 · 深色：灰度随亮度增长的斜率
    private static let clearSlope = 0.79

    /// 色调 · 深色：亮度为 0 时各通道的值，与色调颜色无关
    private static let tintedOffset = 0.08

    /// 色调 · 深色：各通道随“亮度 × 色调颜色的对应通道”增长的斜率
    private static let tintedSlope = 0.92

    /// 去色：灰度 = 0.075 + 0.79 × 亮度
    /// - Parameter image: 要处理的图标
    /// - Returns: 处理后的图标，像素尺寸与原图相同；建不起位图上下文时为 nil
    static func clear(_ image: CGImage) -> CGImage? {
        recolor(
            image,
            offset: clearOffset,
            slopes: (clearSlope, clearSlope, clearSlope)
        )
    }

    /// 着色：各通道 = 0.08 + 0.92 × 亮度 × 色调颜色的对应通道
    /// - Parameters:
    ///   - image: 要处理的图标
    ///   - tintColor: 色调颜色；系统颜色这类动态颜色按深色外观取值
    /// - Returns: 处理后的图标，像素尺寸与原图相同；色调颜色转不成 sRGB 或建不起位图上下文时为 nil
    static func tinted(
        _ image: CGImage,
        tintColor: NSColor
    ) -> CGImage? {
        // 系统颜色在深浅外观下取值不同，深色子变体按深色外观取
        #warning("TODO: Dock 截图拟合里深色外观的 systemOrange 只比浅色外观略好，系统实际按哪种外观解析色调颜色未确认")
        var resolved: NSColor? = nil
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            resolved = tintColor.usingColorSpace(.sRGB)
        }

        guard let resolved else { return nil }

        return recolor(
            image,
            offset: tintedOffset,
            slopes: (
                tintedSlope * resolved.redComponent,
                tintedSlope * resolved.greenComponent,
                tintedSlope * resolved.blueComponent
            )
        )
    }
}

// MARK: - Private

extension DarkIconStyleRenderer {
    /// 逐像素把颜色换成亮度的线性函数：各通道 = offset + slopes 的对应分量 × 亮度
    /// - Parameters:
    ///   - image: 要处理的图标
    ///   - offset: 亮度为 0 时各通道的值
    ///   - slopes: 红、绿、蓝各通道随亮度增长的斜率
    /// - Returns: 处理后的图标；建不起位图上下文时为 nil
    private static func recolor(
        _ image: CGImage,
        offset: Double,
        slopes: (red: Double, green: Double, blue: Double)
    ) -> CGImage? {
        let width = image.width
        let height = image.height

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let data = context.data
        else {
            return nil
        }

        // 先画成 sRGB 的 8 位 RGBA 位图：系数是在 sRGB 编码值上拟合的，icns 的色彩空间在这一步统一
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let pixelCount = width * height
        let pixels = data.bindMemory(to: UInt8.self, capacity: pixelCount * 4)

        for index in 0 ..< pixelCount {
            let base = index * 4
            let alpha = Double(pixels[base + 3]) / 255

            // 全透明的像素（图标四周的透明边）没有颜色可处理
            guard alpha > 0 else { continue }

            // 位图预乘了透明度，先除掉透明度还原出真实颜色，再算亮度
            let luma = 0.2126 * Double(pixels[base]) / 255 / alpha
                + 0.7152 * Double(pixels[base + 1]) / 255 / alpha
                + 0.0722 * Double(pixels[base + 2]) / 255 / alpha

            // 写回时重新乘上透明度，透明度本身不变
            pixels[base] = premultipliedByte(offset + slopes.red * luma, alpha: alpha)
            pixels[base + 1] = premultipliedByte(offset + slopes.green * luma, alpha: alpha)
            pixels[base + 2] = premultipliedByte(offset + slopes.blue * luma, alpha: alpha)
        }

        return context.makeImage()
    }

    /// 把 0–1 的通道值夹进范围、乘上透明度，换成 8 位整数
    /// - Parameters:
    ///   - value: 未预乘的通道值
    ///   - alpha: 像素的透明度，0–1
    private static func premultipliedByte(
        _ value: Double,
        alpha: Double
    ) -> UInt8 {
        UInt8((min(max(value, 0), 1) * alpha * 255).rounded())
    }
}
