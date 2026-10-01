import AppKit

@testable import Flotilla

// MARK: - ThumbnailGeneratorStub

/// 假的缩略图生成：记下每次请求与取消，由测试决定何时交出什么结果；不经 QuickLook，CI 上同样确定
@MainActor
final class ThumbnailGeneratorStub {
    /// 收到的请求，按先后顺序：文件的 URL，与交出结果的回调
    private var requests: [(url: URL, completion: @Sendable (NSImage?) -> Void)] = []

    /// 被取消的请求的文件 URL，按先后顺序
    private(set) var cancelledURLs: [URL] = []

    /// 请求过缩略图的文件 URL，按先后顺序
    var requestedURLs: [URL] {
        requests.map(\.url)
    }

    /// 用这个假实现生成缩略图的加载器
    func makeLoader() -> FileThumbnailLoader {
        FileThumbnailLoader { url, completion in
            self.requests.append((url, completion))

            return {
                self.cancelledURLs.append(url)
            }
        }
    }

    /// 交出某个文件的结果，与 QuickLook 一样经回调送达
    /// - Parameters:
    ///   - url: 文件的 URL
    ///   - thumbnail: 缩略图；为 nil 表示生成不出
    func complete(_ url: URL, with thumbnail: NSImage?) {
        for request in requests where request.url == url {
            request.completion(thumbnail)
        }
    }
}
