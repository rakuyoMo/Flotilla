import AppKit
import Testing

@testable import Flotilla

// MARK: - DarkIconStyleRendererTests

/// “透明 · 深色” “色调 · 深色” 的图标处理：去色后不带色彩，着色后只带色调颜色，明暗顺序与透明度不变；
/// 夜间版处理后仍比白天版暗，Dock 上才是与系统图标一致的深底
struct DarkIconStyleRendererTests {
    /// 要处理的两种变体：透明、色调的深色子变体
    private nonisolated static let processedVariants: [AppIconVariant] = [.clearNight, .tintedNight]

    /// 8 位量化带来的误差上限
    private static let tolerance = 2.0 / 255

    /// App 图标母版所在目录：本文件位于 `Tests/FlotillaTests/` 下，所在目录向上两级是仓库根目录
    private static let resourcesURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/Flotilla/Resources", directoryHint: .isDirectory)

    /// 着色用的色调颜色：固定的 sRGB 颜色，不随外观变化
    private static var tintColor: NSColor {
        NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1)
    }

    /// 各种色彩鲜明的像素，包括夜间版的深蓝底
    private static var colorfulPixels: [Pixel] {
        [
            (1, 0, 0, 1),
            (0, 1, 0, 1),
            (0, 0, 1, 1),
            (1, 0.6, 0.1, 1),
            (0.07, 0.24, 0.45, 1),
        ]
    }

    /// 去色后每个像素的红、绿、蓝相等：透明样式不带任何色彩
    @Test
    func clearRemovesColor() throws {
        let output = try Self.pixels(
            of: Self.render(Self.image(of: Self.colorfulPixels), as: .clearNight)
        )

        for pixel in output {
            #expect(abs(pixel.red - pixel.green) <= Self.tolerance)
            #expect(abs(pixel.green - pixel.blue) <= Self.tolerance)
        }
    }

    /// 着色后亮部的色相与色调颜色一致：色调样式的字形是色调颜色
    @Test
    func tintedTakesTintHue() throws {
        let output = try Self.pixels(
            of: Self.render(
                Self.image(of: [(1, 1, 1, 1), (0.6, 0.6, 0.6, 1)]),
                as: .tintedNight
            )
        )

        for pixel in output {
            let color = NSColor(
                srgbRed: pixel.red,
                green: pixel.green,
                blue: pixel.blue,
                alpha: 1
            )

            #expect(abs(color.hueComponent - Self.tintColor.hueComponent) < 0.01)
            #expect(color.saturationComponent > 0.3)
        }
    }

    /// 黑色变成不带色彩的深色：两种样式的底色都是中性的深色，与色调颜色无关
    @Test(arguments: processedVariants)
    func blackBecomesNeutralDark(variant: AppIconVariant) throws {
        let output = try Self.pixels(
            of: Self.render(Self.image(of: [(0, 0, 0, 1)]), as: variant)
        )

        let pixel = try #require(output.first)

        #expect(abs(pixel.red - pixel.green) <= Self.tolerance)
        #expect(abs(pixel.green - pixel.blue) <= Self.tolerance)
        #expect(pixel.red < 0.1)
    }

    /// 原图越亮，处理后越亮：明暗层次保留下来，图案才认得出
    @Test(arguments: processedVariants)
    func brightnessOrderIsPreserved(variant: AppIconVariant) throws {
        let grays: [Pixel] = [0, 0.25, 0.5, 0.75, 1].map { ($0, $0, $0, 1) }

        let lumas = try Self.pixels(
            of: Self.render(Self.image(of: grays), as: variant)
        )
        .map(Self.luma)

        for (darker, brighter) in zip(lumas, lumas.dropFirst()) {
            #expect(darker < brighter)
        }
    }

    /// 透明度不变：图标四周的透明边仍然透明，半透明的边缘仍然半透明
    @Test(arguments: processedVariants)
    func alphaIsPreserved(variant: AppIconVariant) throws {
        let input: [Pixel] = [
            (0.5, 0.5, 0.5, 0),
            (0.8, 0.4, 0.2, 0.5),
            (0.8, 0.4, 0.2, 1),
        ]

        let output = try Self.pixels(
            of: Self.render(Self.image(of: input), as: variant)
        )

        for (source, result) in zip(input, output) {
            #expect(abs(source.alpha - result.alpha) <= Self.tolerance)
        }
    }

    /// 夜间版处理后整体比白天版暗，且是深底（平均亮度低于一半）：这正是深色子变体要换成夜间版的原因
    @Test(arguments: processedVariants)
    func processedNightIsDarkerThanDay(variant: AppIconVariant) throws {
        let night = try Self.meanLuma(
            of: Self.render(Self.master(named: "AppIconDark"), as: variant)
        )

        let day = try Self.meanLuma(
            of: Self.render(Self.master(named: "AppIcon"), as: variant)
        )

        #expect(night < day)
        #expect(night < 0.5)
    }
}

// MARK: - Private

extension DarkIconStyleRendererTests {
    /// 未预乘透明度的 sRGB 像素，各分量 0–1
    private typealias Pixel = (red: Double, green: Double, blue: Double, alpha: Double)

    /// 按变体处理图像；夜间版原样的变体不经处理
    /// - Parameters:
    ///   - image: 要处理的图像
    ///   - variant: 要生成的变体
    private static func render(
        _ image: CGImage,
        as variant: AppIconVariant
    ) throws -> CGImage {
        switch variant {
        case .night:
            image

        case .clearNight:
            try #require(DarkIconStyleRenderer.clear(image))

        case .tintedNight:
            try #require(DarkIconStyleRenderer.tinted(image, tintColor: tintColor))
        }
    }

    /// 把一排像素做成一行高的 sRGB 图像
    /// - Parameter pixels: 从左到右的像素
    private static func image(of pixels: [Pixel]) throws -> CGImage {
        let context = try bitmapContext(width: pixels.count, height: 1)
        let data = try #require(context.data)
            .bindMemory(to: UInt8.self, capacity: pixels.count * 4)

        // 位图预乘透明度，写入前把颜色乘上透明度
        for (index, pixel) in pixels.enumerated() {
            let components = [
                pixel.red * pixel.alpha,
                pixel.green * pixel.alpha,
                pixel.blue * pixel.alpha,
                pixel.alpha,
            ]

            for (offset, component) in components.enumerated() {
                data[index * 4 + offset] = UInt8((component * 255).rounded())
            }
        }

        return try #require(context.makeImage())
    }

    /// 读出图像的全部像素，除掉透明度还原成未预乘的颜色；全透明的像素颜色记为 0
    private static func pixels(of image: CGImage) throws -> [Pixel] {
        let context = try bitmapContext(width: image.width, height: image.height)

        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        let count = image.width * image.height
        let data = try #require(context.data)
            .bindMemory(to: UInt8.self, capacity: count * 4)

        return (0 ..< count).map { index in
            let alpha = Double(data[index * 4 + 3]) / 255
            let scale = alpha > 0 ? 1 / (255 * alpha) : 0

            return (
                red: Double(data[index * 4]) * scale,
                green: Double(data[index * 4 + 1]) * scale,
                blue: Double(data[index * 4 + 2]) * scale,
                alpha: alpha
            )
        }
    }

    /// 母版缩成 64 × 64 的图像：处理与比较只看整体明暗，缩小后测试更快
    /// - Parameter name: 母版的文件名，不含扩展名
    private static func master(named name: String) throws -> CGImage {
        let url = resourcesURL.appending(path: "\(name).png")
        let source = try #require(
            NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )

        let side = 64
        let context = try bitmapContext(width: side, height: side)

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))

        return try #require(context.makeImage())
    }

    /// 不透明部分的平均亮度，0–1；只数完全不透明的像素，四周的透明边不计入
    private static func meanLuma(of image: CGImage) throws -> Double {
        let lumas = try pixels(of: image)
            .filter { $0.alpha == 1 }
            .map(luma)

        return lumas.reduce(0, +) / Double(max(lumas.count, 1))
    }

    /// 像素的 Rec. 709 亮度（在 sRGB 编码值上计算）
    private static func luma(_ pixel: Pixel) -> Double {
        0.2126 * pixel.red + 0.7152 * pixel.green + 0.0722 * pixel.blue
    }

    /// 8 位 RGBA、预乘透明度的 sRGB 位图上下文
    private static func bitmapContext(
        width: Int,
        height: Int
    ) throws -> CGContext {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))

        return try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
    }
}
