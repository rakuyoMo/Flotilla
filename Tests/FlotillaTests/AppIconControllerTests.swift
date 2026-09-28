import AppKit
import Testing

@testable import Flotilla

// MARK: - AppIconControllerTests

/// App 图标跟随“图标与小组件样式”：深色样式在运行时换成夜间版，其余样式交还包里的默认图标（白天版）
///
/// Dock 只对包里的默认图标做透明、色调处理，透明、色调样式下在运行时设了图标，Dock 就不再按样式处理；
/// 资源名落到 `Sources/Flotilla/Resources` 下同名的母版上比较画面，深浅取反或母版对调都会失败
@MainActor
struct AppIconControllerTests {
    /// 要换成夜间版的样式与外观：深色 · 始终不看外观，深色 · 自动只在深色外观（含高对比度、vibrant 变体）下
    private nonisolated static let nightCases: [(iconTheme: String, appearance: NSAppearance.Name)] = [
        ("RegularDark", .darkAqua),
        ("RegularDark", .aqua),
        ("RegularAutomatic", .darkAqua),
        ("RegularAutomatic", .accessibilityHighContrastDarkAqua),
        ("RegularAutomatic", .vibrantDark),
    ]

    /// 用包里默认图标的样式与外观：默认（键不存在）、深色 · 自动遇到浅色外观、透明与色调的各个子变体
    private nonisolated static let bundleIconCases: [(iconTheme: String?, appearance: NSAppearance.Name)] = [
        (nil, .darkAqua),
        (nil, .aqua),
        ("RegularAutomatic", .aqua),
        ("RegularAutomatic", .accessibilityHighContrastAqua),
        ("RegularAutomatic", .vibrantLight),
        ("ClearLight", .darkAqua),
        ("ClearDark", .darkAqua),
        ("ClearAutomatic", .darkAqua),
        ("TintedLight", .darkAqua),
        ("TintedDark", .darkAqua),
        ("TintedAutomatic", .darkAqua),
    ]

    /// App 图标母版所在目录：本文件位于 `Tests/FlotillaTests/` 下，所在目录向上两级是仓库根目录
    private static let resourcesURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/Flotilla/Resources", directoryHint: .isDirectory)

    /// 深色样式换上的是夜间版：它的母版整体比 Info.plist 指定的默认图标暗
    @Test(arguments: nightCases)
    func darkStyleUsesNightIcon(
        iconTheme: String,
        appearance: NSAppearance.Name
    ) throws {
        let effectiveAppearance = try #require(NSAppearance(named: appearance))
        let name = try #require(
            AppIconController.iconName(
                forIconTheme: iconTheme,
                appearance: effectiveAppearance
            )
        )

        let nightBrightness = try Self.meanBrightness(ofMasterNamed: name)
        let defaultBrightness = try Self.meanBrightness(ofMasterNamed: Self.defaultIconName())

        #expect(nightBrightness < defaultBrightness)
    }

    /// 其余样式不在运行时设图标，Dock 显示包里的默认图标并按样式处理
    @Test(arguments: bundleIconCases)
    func otherStylesKeepBundleIcon(
        iconTheme: String?,
        appearance: NSAppearance.Name
    ) throws {
        let name = try AppIconController.iconName(
            forIconTheme: iconTheme,
            appearance: #require(NSAppearance(named: appearance))
        )

        #expect(name == nil)
    }
}

// MARK: - Private

extension AppIconControllerTests {
    /// Info.plist 里 `CFBundleIconFile` 指定的默认图标名，也是它的母版文件名
    private static func defaultIconName() throws -> String {
        let infoURL = resourcesURL
            .deletingLastPathComponent()
            .appending(path: "Info.plist")

        let propertyList = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: infoURL),
            format: nil
        )

        let info = try #require(propertyList as? [String: Any])

        return try #require(info["CFBundleIconFile"] as? String)
    }

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
