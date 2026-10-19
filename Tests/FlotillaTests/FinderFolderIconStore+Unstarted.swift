import Foundation

@testable import Flotilla

// MARK: - FinderFolderIconStore + Unstarted

extension FinderFolderIconStore {
    /// 没有开始监听的图标库：跟着一棵空的组树，不读扩展属性、不取图，访达文件夹都用 `FileReference.icon`
    ///
    /// 给不关心访达文件夹外观的测试用；组树的持久化文件在临时目录里、并不存在，不碰 App 的数据
    static func unstarted() -> FinderFolderIconStore {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "FlotillaTests-\(UUID().uuidString)/folders.json")

        return FinderFolderIconStore(store: GroupStore(fileURL: fileURL))
    }
}
