import AppKit

// MARK: - IconFileWriter

/// 把 `NSImage` 写成 `.icns`，作为 stub bundle 的图标
enum IconFileWriter {
    /// iconset 包含的点尺寸，每档再各输出一张 @2x
    private static let pointSides = [16, 32, 128, 256, 512]

    /// 把图像写成 `.icns`
    /// - Parameters:
    ///   - image: 要写入的图像，按每档的目标像素尺寸重新栅格化
    ///   - url: 输出的 `.icns` 文件位置，已存在时覆盖
    /// - Throws: 栅格化失败时抛出 `DockTileError.rasterizationFailed`；
    ///   `iconutil` 失败时抛出 `DockTileError.commandFailed`；
    ///   读写临时文件失败时抛出文件错误
    static func write(_ image: NSImage, to url: URL) throws {
        let fileManager = FileManager.default

        // iconutil 只接受目录名以 .iconset 结尾的输入，放在临时目录里用完即删
        let iconsetURL = fileManager.temporaryDirectory
            .appending(
                path: "Flotilla-\(UUID().uuidString).iconset",
                directoryHint: .isDirectory
            )

        try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: iconsetURL) }

        // 按 iconutil 约定的文件名写出 10 张 PNG
        for pointSide in pointSides {
            for scale in [1, 2] {
                let suffix = scale == 1 ? "" : "@2x"
                let fileName = "icon_\(pointSide)x\(pointSide)\(suffix).png"

                let data = try pngData(of: image, pixelSide: pointSide * scale)
                try data.write(to: iconsetURL.appending(path: fileName))
            }
        }

        try CommandRunner.run(
            "/usr/bin/iconutil",
            arguments: [
                "--convert", "icns",
                "--output", url.path(percentEncoded: false),
                iconsetURL.path(percentEncoded: false),
            ]
        )
    }

    /// 把图像栅格化为边长 pixelSide 像素的 PNG；
    /// 建不出位图或编码失败时抛出 `DockTileError.rasterizationFailed`
    private static func pngData(of image: NSImage, pixelSide: Int) throws -> Data {
        guard
            let bitmap = NSBitmapImageRep(
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
        else {
            throw DockTileError.rasterizationFailed(pixelSide: pixelSide)
        }

        // 点尺寸等于像素尺寸，绘制时 1 点对应 1 像素
        let canvas = NSRect(x: 0, y: 0, width: pixelSide, height: pixelSide)
        bitmap.size = canvas.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: canvas)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw DockTileError.rasterizationFailed(pixelSide: pixelSide)
        }

        return data
    }
}
