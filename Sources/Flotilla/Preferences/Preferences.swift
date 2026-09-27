import Foundation

// MARK: - Preferences

/// 用户设置：预览图标数（需求 2）
@MainActor
final class Preferences {
    /// 预览图标数的上限：文件夹图标正面的 2×2 网格最多容纳 4 个
    nonisolated static let maximumPreviewIconCount = 4

    /// 设置发生变更后发出的通知，`object` 为发生变更的 `Preferences`
    nonisolated static let didChangeNotification = Notification.Name("Preferences.didChange")

    /// App 使用的实例，读写 `UserDefaults.standard`
    static let shared = Preferences(defaults: .standard)

    /// 预览图标数在 `UserDefaults` 里的键
    private static let previewIconCountKey = "previewIconCount"

    /// 存放设置的 `UserDefaults`
    private let defaults: UserDefaults

    /// 渲染进文件夹图标的 App 图标数量，默认取上限 4；读写都夹在 `0...maximumPreviewIconCount`
    var previewIconCount: Int {
        get {
            let stored = defaults.object(forKey: Self.previewIconCountKey) as? Int
            return Self.clamped(stored ?? Self.maximumPreviewIconCount)
        }
        set {
            let value = Self.clamped(newValue)
            guard value != previewIconCount else { return }

            defaults.set(value, forKey: Self.previewIconCountKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    /// 创建设置对象
    /// - Parameter defaults: 存放设置的 `UserDefaults`，测试时注入独立的 suite
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 把预览图标数夹到 `0...maximumPreviewIconCount`
    private static func clamped(_ count: Int) -> Int {
        min(max(count, 0), maximumPreviewIconCount)
    }
}
