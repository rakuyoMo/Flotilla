import AppKit
import os

// MARK: - AppIconController

/// Flotilla 自身的 App 图标：Dock 与 ⌘Tab 里的图标跟随系统设置“外观 › 图标与小组件样式”
///
/// 访达等处只认包里的默认图标（白天版）：没有 Assets.car，换成夜间版只能在运行时作用于 Dock 与 ⌘Tab。
/// Dock 只对包里的默认图标做透明、色调处理，运行时设置的图标一律原样显示（macOS 27 实测），
/// 所以只有深色样式在运行时换成夜间版，其余样式都交还包里的默认图标
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

    /// 运行时要换上的图标资源名；nil 表示用包里的默认图标，由 Dock 按样式处理
    ///
    /// 深色样式分“始终”（`RegularDark`）与“自动”（`RegularAutomatic`，跟随系统深浅外观）；
    /// 透明、色调样式的取值以 `Clear`、`Tinted` 开头
    ///
    /// 没有“图标与小组件样式”的系统（macOS 15 起、26 之前）上 `iconTheme` 总是 nil，同样用默认图标，与系统里其它 App 一致
    /// - Parameters:
    ///   - iconTheme: 全局偏好 `AppleIconAppearanceTheme` 的值，“默认”样式时为 nil
    ///   - appearance: App 的 `effectiveAppearance`，只在“深色 · 自动”时起作用；高对比度等变体归入对应的深色或浅色
    static func iconName(
        forIconTheme iconTheme: String?,
        appearance: NSAppearance
    ) -> String? {
        switch iconTheme {
        case "RegularDark":
            darkIconName

        case "RegularAutomatic":
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? darkIconName
                : nil

        default:
            nil
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

        // “深色 · 自动”跟随系统深浅；外观在主线程上变化，观察回调也在主线程
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
        let name = Self.iconName(
            forIconTheme: UserDefaults.standard.string(forKey: Self.iconThemeKey),
            appearance: NSApp.effectiveAppearance
        )

        // 设为 nil 后 Dock 改回显示包里的默认图标，并按透明、色调样式重新处理
        guard let name else {
            NSApp.applicationIconImage = nil
            return
        }

        // 直接运行可执行文件、没有 .app 包时取不到资源
        guard let icon = Bundle.main.image(forResource: name) else {
            Self.logger.error("找不到 App 图标资源 \(name, privacy: .public)，保持系统默认")
            return
        }

        NSApp.applicationIconImage = icon
    }
}
