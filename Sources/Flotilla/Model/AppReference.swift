import AppKit
import UniformTypeIdentifiers

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

// MARK: - Content Type

extension AppReference {
    /// URL 是否指向 App bundle：内容类型符合 `.applicationBundle`；文件不存在时为否
    ///
    /// 设置窗口从访达拖入、把 App 拖到 Dock 上的 tile，两处按同一个标准判断
    static func isApplicationBundle(_ url: URL) -> Bool {
        let contentType = try? url
            .resourceValues(forKeys: [.contentTypeKey])
            .contentType

        return contentType?.conforms(to: .applicationBundle) ?? false
    }
}
