import Foundation

// MARK: - Preferences

/// 用户设置：预览图标数（需求 2），访达里的文件夹在面板里展开时是否显示隐藏文件（需求 23）
@MainActor
final class Preferences {
    /// 预览图标数的上限：文件夹图标正面的 2×2 网格最多容纳 4 个
    nonisolated static let maximumPreviewIconCount = 4

    /// 预览图标数变更后发出的通知，`object` 为发生变更的 `Preferences`；Dock 上 tile 的图标据此重画
    ///
    /// 是否显示隐藏文件不发这个通知：它与 tile 的图标无关，面板下一次读目录时取当时的值
    nonisolated static let didChangeNotification = Notification.Name("Preferences.didChange")

    /// App 使用的实例，读写 `UserDefaults.standard`
    static let shared = Preferences(defaults: .standard)

    /// 预览图标数在 `UserDefaults` 里的键
    private static let previewIconCountKey = "previewIconCount"

    /// 是否显示隐藏文件在 `UserDefaults` 里的键
    private static let showsHiddenFilesKey = "showsHiddenFiles"

    /// 存放设置的 `UserDefaults`
    private let defaults: UserDefaults

    /// 渲染进文件夹图标的预览图标数量：按顺序取前几个 App、文件或网页，默认取上限 4；读写都夹在 `0...maximumPreviewIconCount`
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

    /// 访达里的文件夹在面板里展开时是否显示隐藏文件，默认不显示
    var showsHiddenFiles: Bool {
        get {
            defaults.bool(forKey: Self.showsHiddenFilesKey)
        }
        set {
            defaults.set(newValue, forKey: Self.showsHiddenFilesKey)
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
