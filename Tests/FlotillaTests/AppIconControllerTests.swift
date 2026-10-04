import AppKit
import Testing

@testable import Flotilla

// MARK: - AppIconControllerTests

/// App 图标跟随“图标与小组件样式”：深色样式与透明、色调的深色子变体换成夜间版，其余样式交还包里的默认图标（白天版）
///
/// Dock 对运行时设置的图标原样显示，只对包里的默认图标做透明、色调处理：
/// 深色子变体不换图标就会是浅底，浅色子变体换了图标就失去系统的处理
@MainActor
struct AppIconControllerTests {
    /// 各样式在深浅外观下应换上的图标；nil 表示不设运行时图标
    ///
    /// “始终”与“深色”子变体不看外观；“自动”子变体只在深色外观（含高对比度、vibrant 变体）下换；
    /// 默认样式（键不存在）与透明、色调的浅色子变体在任何外观下都不换
    private nonisolated static let cases: [(
        iconTheme: String?,
        appearance: NSAppearance.Name,
        variant: AppIconVariant?
    )] = [
        (nil, .darkAqua, nil),
        (nil, .aqua, nil),

        ("RegularDark", .darkAqua, .night),
        ("RegularDark", .aqua, .night),
        ("RegularAutomatic", .darkAqua, .night),
        ("RegularAutomatic", .accessibilityHighContrastDarkAqua, .night),
        ("RegularAutomatic", .vibrantDark, .night),
        ("RegularAutomatic", .aqua, nil),
        ("RegularAutomatic", .accessibilityHighContrastAqua, nil),
        ("RegularAutomatic", .vibrantLight, nil),

        ("ClearLight", .darkAqua, nil),
        ("ClearLight", .aqua, nil),
        ("ClearDark", .darkAqua, .clearNight),
        ("ClearDark", .aqua, .clearNight),
        ("ClearAutomatic", .darkAqua, .clearNight),
        ("ClearAutomatic", .aqua, nil),

        ("TintedLight", .darkAqua, nil),
        ("TintedLight", .aqua, nil),
        ("TintedDark", .darkAqua, .tintedNight),
        ("TintedDark", .aqua, .tintedNight),
        ("TintedAutomatic", .darkAqua, .tintedNight),
        ("TintedAutomatic", .aqua, nil),
    ]

    /// 样式与外观决定换上哪一版图标
    @Test(arguments: cases)
    func variantFollowsIconStyle(
        iconTheme: String?,
        appearance: NSAppearance.Name,
        variant: AppIconVariant?
    ) throws {
        let effectiveAppearance = try #require(NSAppearance(named: appearance))

        let actual = AppIconController.variant(
            forIconTheme: iconTheme,
            appearance: effectiveAppearance
        )

        #expect(actual == variant)
    }
}
