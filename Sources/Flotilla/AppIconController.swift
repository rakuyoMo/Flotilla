import AppKit
import os

// MARK: - AppIconController

/// Flotilla 自身的 App 图标：Dock 与 ⌘Tab 里的图标跟随系统设置“外观 › 图标与小组件样式”
///
/// 访达等处只认包里的默认图标（白天版）：没有 Assets.car，换成夜间版只能在运行时作用于 Dock 与 ⌘Tab。
/// Dock 只对包里的默认图标做透明、色调处理，运行时设置的图标一律原样显示（macOS 27 实测），
/// 所以深色样式与透明、色调的深色子变体都在运行时换成处理好的夜间版，其余样式交还包里的默认图标
@MainActor
final class AppIconController: NSObject {
    /// 夜间版图标在包里的资源名
    private static let darkIconName = "AppIconDark"

    /// “图标与小组件样式”在全局偏好里的键；选“默认”时键不存在
    private static let iconThemeKey = "AppleIconAppearanceTheme"

    /// “图标与小组件样式”变化时 `NSWorkspace` 的通知中心发出的通知；名称不在公开头文件里，macOS 27 实测
    private static let iconAppearanceDidChangeNotification = Notification.Name(
        "NSWorkspaceIconAppearanceConfigurationDidChangeNotification"
    )

    /// App 图标相关的日志
    private static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "AppIconController"
    )

    /// 对“图标与小组件样式”变化的观察
    private var iconStyleObservation: (any NSObjectProtocol)?

    /// 对 App 外观的观察：App 没有固定外观，这个值跟随系统的深浅
    private var appearanceObservation: NSKeyValueObservation?

    /// 运行时要换上的图标；nil 表示用包里的默认图标，由 Dock 按样式处理
    ///
    /// 深色、透明、色调三种样式各有深色、自动两个子变体要换成夜间版：取值以 `Dark` 结尾的始终换，
    /// 以 `Automatic` 结尾的跟随系统深浅外观，只在深色外观下换；透明、色调的浅色子变体（`Light` 结尾）交给系统处理白天版
    ///
    /// 没有“图标与小组件样式”的系统（macOS 15 起、26 之前）上 `iconTheme` 总是 nil，同样用默认图标，与系统里其它 App 一致
    /// - Parameters:
    ///   - iconTheme: 全局偏好 `AppleIconAppearanceTheme` 的值，“默认”样式时为 nil
    ///   - appearance: App 的 `effectiveAppearance`，只在“自动”子变体下起作用；高对比度等变体归入对应的深色或浅色
    static func variant(
        forIconTheme iconTheme: String?,
        appearance: NSAppearance
    ) -> AppIconVariant? {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        switch iconTheme {
        case "RegularDark":
            return .night

        case "RegularAutomatic":
            return isDark ? .night : nil

        case "ClearDark":
            return .clearNight

        case "ClearAutomatic":
            return isDark ? .clearNight : nil

        case "TintedDark":
            return .tintedNight

        case "TintedAutomatic":
            return isDark ? .tintedNight : nil

        default:
            return nil
        }
    }

    /// 按当前样式设一次图标，此后在 Flotilla 被激活、样式变化、系统深浅切换时重新设置
    func start() {
        updateIcon()

        // Flotilla 只在打开设置窗口时切到 `.regular` 并激活，Dock 这时才为它建立图标，显示的是包里的默认图标：
        // `.accessory` 期间设的图标不会沿用，激活后要再设一次
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateIcon),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        // 样式或色调颜色变化时 AppKit 发出这条通知，此时全局偏好已是新值
        iconStyleObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: Self.iconAppearanceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateIcon()
            }
        }

        // 各样式的“自动”子变体跟随系统深浅；外观在主线程上变化，观察回调也在主线程
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.updateIcon()
            }
        }
    }
}

// MARK: - Private

extension AppIconController {
    /// 把 App 图标设成当前样式对应的一版；不需要换时交还包里的默认图标
    @objc
    private func updateIcon() {
        let variant = Self.variant(
            forIconTheme: UserDefaults.standard.string(forKey: Self.iconThemeKey),
            appearance: NSApp.effectiveAppearance
        )

        // 设为 nil 后 Dock 改回显示包里的默认图标，并按透明、色调样式重新处理
        guard let variant else {
            NSApp.applicationIconImage = nil
            return
        }

        // 取不到或处理不了时保持现有图标，原因已由 `icon(for:)` 记入日志
        guard let icon = Self.icon(for: variant) else { return }

        NSApp.applicationIconImage = icon
    }
}

// MARK: - Helpers

extension AppIconController {
    /// 按变体生成运行时图标：夜间版原样，或按当前色调颜色去色、着色
    /// - Parameter variant: 要生成的变体
    /// - Returns: 生成的图标；取不到夜间版资源或处理失败时为 nil
    private static func icon(for variant: AppIconVariant) -> NSImage? {
        // 直接运行可执行文件、没有 .app 包时取不到资源
        guard let nightIcon = Bundle.main.image(forResource: darkIconName) else {
            logger.error("找不到 App 图标资源 \(darkIconName, privacy: .public)，保持现有图标")
            return nil
        }

        // 夜间版原样返回；透明、色调先定下处理方式，色调颜色在这时取当前值
        let render: (CGImage) -> CGImage?

        switch variant {
        case .night:
            return nightIcon

        case .clearNight:
            render = DarkIconStyleRenderer.clear

        case .tintedNight:
            let tintColor = iconTintColor()
            render = { DarkIconStyleRenderer.tinted($0, tintColor: tintColor) }
        }

        // 取 icns 里最大的一张来处理：Dock 放大时也要清晰
        var rect = CGRect(x: 0, y: 0, width: 1024, height: 1024)

        guard let source = nightIcon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            logger.error("夜间版图标转不成位图，保持现有图标")
            return nil
        }

        guard let processed = render(source) else {
            logger.error("处理夜间版图标失败，保持现有图标")
            return nil
        }

        return NSImage(cgImage: processed, size: nightIcon.size)
    }

    /// “图标与小组件样式”当前的色调颜色；选“自动”时是系统解析出的颜色
    ///
    /// 全局偏好只存颜色名，“自动”时连名字都没有，解析后的颜色要从 `NSWorkspace` 的私有配置对象取：
    /// `currentIconAppearanceConfiguration` 返回 SkyLight 的 `SLSIconAppearanceConfiguration`，
    /// 其 `resolvedIconTintColor` 是 `NSColor`（macOS 27 实测，“自动”时为 `systemBlueColor`）；取不到时退回强调色
    private static func iconTintColor() -> NSColor {
        let configurationSelector = NSSelectorFromString("currentIconAppearanceConfiguration")
        let tintColorKey = "resolvedIconTintColor"

        // 私有接口，逐步确认存在再取，任何一步不满足都退回强调色
        guard
            NSWorkspace.shared.responds(to: configurationSelector),
            let configuration = NSWorkspace.shared
                .perform(configurationSelector)?
                .takeUnretainedValue() as? NSObject,
            configuration.responds(to: NSSelectorFromString(tintColorKey)),
            let tintColor = configuration.value(forKey: tintColorKey) as? NSColor
        else {
            logger.error("取不到“图标与小组件样式”的色调颜色，改用强调色")
            return .controlAccentColor
        }

        return tintColor
    }
}
