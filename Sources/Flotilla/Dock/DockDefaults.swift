import Foundation

// MARK: - DockDefaults

/// Dock 偏好域的 `UserDefaults`：把 tile 所在的区域暴露成能用 KeyPath 观察的属性
///
/// 键名 `persistent-apps` 带连字符，写不成 KeyPath，借 KVO 的依赖键让 `tiles` 随它一起通知。
/// 实测（macOS 27）以域名创建时，Dock 等其它进程写入这个键同样会通知，写入后随即送达；
/// 偏好文件要等 cfprefsd 落盘，Dock 自己的写入有时要晚 5 秒以上才出现在文件里，不能靠监听文件
final class DockDefaults: UserDefaults {
    /// tile 所在区域的键：Dock 左侧的 App 区域
    static let tilesKey = "persistent-apps"

    /// `tiles` 随 `persistent-apps` 的变化一起发出 KVO 通知
    @objc
    class var keyPathsForValuesAffectingTiles: Set<String> {
        [tilesKey]
    }

    /// 区域内当前的全部条目
    @objc
    dynamic var tiles: [[String: Any]] {
        array(forKey: Self.tilesKey) as? [[String: Any]] ?? []
    }
}
