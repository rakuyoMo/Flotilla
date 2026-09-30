import AppKit

// MARK: - FileReference

/// 对一个文件的引用：访达里 App 以外的一切，包括文件包、访达里的文件夹与卷
///
/// 带着书签：文件移动或改名后，按书签找到新位置
struct FileReference: BookmarkedReference, Codable, Hashable, Identifiable {
    /// 这一项的唯一标识；同一个文件放进不同文件夹时各有各的 id
    let id: UUID

    /// 文件的 URL；文件包、访达里的文件夹与卷是目录 URL，其余是文件 URL
    let url: URL

    /// 文件的书签，文件移动或改名后据此找到新位置；建不起来时为 nil，只按路径找
    let bookmark: Data?
}

// MARK: - Display

extension FileReference {
    /// 文件在访达中显示的名称
    var displayName: String {
        FileManager.default.displayName(atPath: url.path(percentEncoded: false))
    }

    /// 文件在访达中的图标
    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
    }
}
