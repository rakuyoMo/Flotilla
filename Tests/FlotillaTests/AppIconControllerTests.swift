import AppKit
import Testing

@testable import Flotilla

// MARK: - AppIconControllerTests

/// App 图标跟随系统外观：深色外观取夜间版、浅色外观取白天版，白天版同时是包的默认图标
///
/// 资源名落到 `Sources/Flotilla/Resources` 下同名的母版上比较画面，深浅取反或母版对调都会失败
@MainActor
struct AppIconControllerTests {
    /// 成对的深色、浅色外观：基础外观与高对比度、vibrant 变体
    private nonisolated static let appearancePairs: [(dark: NSAppearance.Name, light: NSAppearance.Name)] = [
        (.darkAqua, .aqua),
        (.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua),
        (.vibrantDark, .vibrantLight),
    ]

    /// App 图标母版所在目录：本文件位于 `Tests/FlotillaTests/` 下，所在目录向上两级是仓库根目录
    private static let resourcesURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/Flotilla/Resources", directoryHint: .isDirectory)

    /// 深色外观取到的是夜间版：它的母版整体比浅色外观取到的暗
    @Test(arguments: appearancePairs)
    func darkAppearanceUsesNightIcon(
        dark: NSAppearance.Name,
        light: NSAppearance.Name
    ) throws {
        let darkName = try AppIconController.iconName(for: #require(NSAppearance(named: dark)))
        let lightName = try AppIconController.iconName(for: #require(NSAppearance(named: light)))

        let darkBrightness = try Self.meanBrightness(ofMasterNamed: darkName)
        let lightBrightness = try Self.meanBrightness(ofMasterNamed: lightName)

        #expect(darkBrightness < lightBrightness)
    }

    /// 浅色外观取到的白天版就是 Info.plist 指定的默认图标，访达等处显示的也是它
    @Test
    func defaultIconIsDaytimeIcon() throws {
        let infoURL = Self.resourcesURL
            .deletingLastPathComponent()
            .appending(path: "Info.plist")

        let propertyList = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: infoURL),
            format: nil
        )

        let info = try #require(propertyList as? [String: Any])
        let aqua = try #require(NSAppearance(named: .aqua))

        #expect(info["CFBundleIconFile"] as? String == AppIconController.iconName(for: aqua))
    }
}

// MARK: - Private

extension AppIconControllerTests {
    /// 母版的平均亮度，0–255
    /// - Parameter name: 母版的文件名，不含扩展名
    private static func meanBrightness(ofMasterNamed name: String) throws -> Double {
        let url = resourcesURL.appending(path: "\(name).png")
        let image = try #require(
            NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )

        // 缩成 64 × 64 的灰度位图再平均：位图没有透明通道，透明边合成在黑色上，两版的透明边相同，不影响比较
        let side = 64
        let context = try #require(
            CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        )

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        let pixels = try #require(context.data)
            .bindMemory(to: UInt8.self, capacity: side * side)

        let total = UnsafeBufferPointer(start: pixels, count: side * side)
            .reduce(0) { $0 + Int($1) }

        return Double(total) / Double(side * side)
    }
}
