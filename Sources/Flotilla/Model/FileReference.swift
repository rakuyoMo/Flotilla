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

    /// 同一个文件换成给定位置与书签后的引用，id 不变
    /// - Parameters:
    ///   - url: 新的位置
    ///   - bookmark: 新的书签；建不起来时为 nil
    func replacingLocation(with url: URL, bookmark: Data?) -> Self {
        Self(id: id, url: url, bookmark: bookmark)
    }
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

// MARK: - Finder Folder

extension FileReference {
    /// 是否是访达里的文件夹：目录且不是文件包，含卷；文件包、符号链接、替身与读不到属性（已删除）的都不是
    ///
    /// 面板里据此决定点击后在面板里展开它，还是交给默认 App 打开；设置窗口据此标出它所在的位置
    var isFinderFolder: Bool {
        // 读不到属性（已删除）时不是
        guard
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey]),
            let isDirectory = values.isDirectory,
            let isPackage = values.isPackage
        else {
            return false
        }

        return isDirectory && !isPackage
    }
}
