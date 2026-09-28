import AppKit
import os

// MARK: - AppIconController

/// Flotilla 自身的 App 图标：Dock 与 ⌘Tab 里的图标随系统深浅外观，在白天版与夜间版之间切换
///
/// 访达等处只显示包里的默认图标（白天版）：macOS 27 不读 icns 内嵌的深色变体，随外观切换只能在运行时设置
@MainActor
final class AppIconController: NSObject {
    /// 白天版图标在包里的资源名，也是 Info.plist 里 `CFBundleIconFile` 指向的默认图标
    private static let lightIconName = "AppIcon"

    /// 夜间版图标在包里的资源名
    private static let darkIconName = "AppIconDark"

    /// App 图标相关的日志
    private static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "AppIconController"
    )

    /// 对 App 外观的观察：App 没有固定外观，这个值跟随系统的深浅
    private var appearanceObservation: NSKeyValueObservation?

    /// 与外观对应的图标资源名：深色取夜间版，浅色取白天版；高对比度等变体归入对应的深色或浅色
    /// - Parameter appearance: App 的 `effectiveAppearance`
    static func iconName(for appearance: NSAppearance) -> String {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? darkIconName
            : lightIconName
    }

    /// 按当前外观设一次图标，此后在 Flotilla 被激活时、系统深浅切换时换成对应的一版
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

        // 外观在主线程上变化，观察回调也在主线程
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.updateIcon()
            }
        }
    }
}

// MARK: - Private

extension AppIconController {
    /// 把 App 图标设成当前外观对应的一版；包里没有图标资源时保持系统默认
    ///
    /// 深浅两版都从包里的 icns 显式设置，两种外观下 Dock 图标的大小与轮廓一致
    @objc
    private func updateIcon() {
        let name = Self.iconName(for: NSApp.effectiveAppearance)

        // 直接运行可执行文件、没有 .app 包时取不到资源
        guard let icon = Bundle.main.image(forResource: name) else {
            Self.logger.error("找不到 App 图标资源 \(name, privacy: .public)，保持系统默认")
            return
        }

        NSApp.applicationIconImage = icon
    }
}
