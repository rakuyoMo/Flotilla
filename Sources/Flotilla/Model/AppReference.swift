import AppKit

// MARK: - AppReference

/// 对一个 App bundle 的引用
struct AppReference: Codable, Hashable, Identifiable {
    /// 这一项的唯一标识；同一个 App 放进不同文件夹时各有各的 id
    let id: UUID

    /// App bundle 的文件 URL
    let url: URL
}

// MARK: - Display

extension AppReference {
    /// App 在访达中显示的名称
    var displayName: String {
        FileManager.default.displayName(atPath: url.path(percentEncoded: false))
    }

    /// App 的图标
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}
