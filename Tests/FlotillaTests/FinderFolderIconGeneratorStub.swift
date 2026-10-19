import AppKit

@testable import Flotilla

// MARK: - FinderFolderIconGeneratorStub

/// 假的访达文件夹取图：记下每次取图，立即交出一张新的纯色图，不经 QuickLook
///
/// 每次交出的都是新的图像对象，测试按对象身份判断换没换图
@MainActor
final class FinderFolderIconGeneratorStub {
    /// 取过图的文件夹 URL，按先后
    private(set) var requestedURLs: [URL] = []

    /// 是否取得出；为 false 时交出 nil，与 QuickLook 报错相同
    var generatesIcons = true

    /// 用这个假实现取图的图标库
    /// - Parameter store: 图标库跟着的组树
    func makeIconStore(following store: GroupStore) -> FinderFolderIconStore {
        FinderFolderIconStore(store: store) { url, completion in
            self.requestedURLs.append(url)

            completion(self.generatesIcons ? SolidColorIcon.make(red: 255) : nil)
        }
    }
}
