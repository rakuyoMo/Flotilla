import Foundation

// MARK: - FolderPanelLevelContent

/// 面板里一个层级展示的内容：Flotilla 的文件夹，或访达里的文件夹
enum FolderPanelLevelContent: Equatable {
    /// Flotilla 的文件夹：网格是它的各项
    case folder(Folder)

    /// 访达里的文件夹：网格是目录里的各项，末尾另有一格“在访达中打开”
    case finderFolder(FileReference, items: [FolderItem])

    /// 这一层的 id：文件夹的 id，或访达里的文件夹这一项的 id；返回时按它在父层级里找到缩回的图标
    var id: UUID {
        switch self {
        case .folder(let folder):
            folder.id

        case .finderFolder(let finderFolder, _):
            finderFolder.id
        }
    }

    /// 标题区显示的名称：文件夹名，或访达里的文件夹在访达中显示的名称
    var title: String {
        switch self {
        case .folder(let folder):
            folder.name

        case .finderFolder(let finderFolder, _):
            finderFolder.displayName
        }
    }

    /// 网格里的项，顺序即展示顺序
    var items: [FolderItem] {
        switch self {
        case .folder(let folder):
            folder.items

        case .finderFolder(_, let items):
            items
        }
    }

    /// “在访达中打开”打开的目录；Flotilla 的文件夹没有这一格（需求 4），为 nil
    var finderFolderURL: URL? {
        guard case .finderFolder(let finderFolder, _) = self else { return nil }

        return finderFolder.url
    }

    /// 网格里的文件是否显示内容缩略图：访达里的文件夹与原生叠放一致显示缩略图，Flotilla 的文件夹照旧显示图标
    var showsFileThumbnails: Bool {
        switch self {
        case .folder:
            false

        case .finderFolder:
            true
        }
    }

    /// 网格的格数：访达里的文件夹多出末尾的“在访达中打开”，空目录也有这一格
    var cellCount: Int {
        finderFolderURL == nil ? items.count : items.count + 1
    }
}
