import AppKit

@testable import Flotilla

// MARK: - ThumbnailGeneratorStub

/// 假的缩略图生成：记下每次请求与取消，由测试决定何时交出什么结果；不经 QuickLook，CI 上同样确定
@MainActor
final class ThumbnailGeneratorStub {
    /// 收到的请求，按先后顺序：文件的 URL，与交出结果的回调
    private var requests: [(url: URL, completion: @Sendable (NSImage?) -> Void)] = []

    /// 已结束的请求在 `requests` 里的位置：被取消，或已交出结果
    private var finishedRequestIndices = IndexSet()

    /// 被取消的请求的文件 URL，按先后顺序
    private(set) var cancelledURLs: [URL] = []

    /// 请求过缩略图的文件 URL，按先后顺序
    var requestedURLs: [URL] {
        requests.map(\.url)
    }

    /// 还没交出结果、也没被取消的请求的文件 URL，按请求的先后顺序
    var pendingURLs: [URL] {
        requests.indices
            .filter { !finishedRequestIndices.contains($0) }
            .map { requests[$0].url }
    }

    /// 用这个假实现生成缩略图的加载器
    func makeLoader() -> FileThumbnailLoader {
        FileThumbnailLoader { url, completion in
            let index = self.requests.count

            self.requests.append((url, completion))

            return {
                self.cancelledURLs.append(url)
                self.finishedRequestIndices.insert(index)
            }
        }
    }

    /// 交出某个文件的结果，与 QuickLook 一样经回调送达；这个文件被取消过的请求同样收到，用来检验晚到的结果被丢掉
    /// - Parameters:
    ///   - url: 文件的 URL
    ///   - thumbnail: 缩略图；为 nil 表示生成不出
    func complete(_ url: URL, with thumbnail: NSImage?) {
        for (index, request) in requests.enumerated() where request.url == url {
            finishedRequestIndices.insert(index)
            request.completion(thumbnail)
        }
    }
}
