import Foundation
import LinkPresentation

// MARK: - WebPageTitleFetcher

/// 用系统的 LinkPresentation 取网页的标题：“添加网页…” 的标题框留空时，自动带入网页的标题
///
/// 跳转、编码与 HTML 实体都由 LinkPresentation 处理
enum WebPageTitleFetcher {
    /// 取一次标题最多等多久
    private static let timeout: TimeInterval = 10

    /// 开始取一个网址的标题，在主线程把结果交给 completionHandler；失败、超时、被取消或网页没有标题时为 nil
    ///
    /// 不隔离到主线程：LinkPresentation 在后台队列调用完成回调
    /// - Parameters:
    ///   - url: 网页的网址
    ///   - completionHandler: 在主线程收到网页的标题，原样不做处理
    /// - Returns: 取消这一次的闭包；取消之后 LinkPresentation 仍会调用完成回调，结果为 nil
    static func fetchTitle(
        of url: URL,
        completionHandler: @escaping @MainActor (String?) -> Void
    ) -> () -> Void {
        // 每个 provider 只能取一次
        let provider = LPMetadataProvider()

        // 只要标题：不下载图标、预览图等附带资源，实测（macOS 27）耗时约为默认的一半
        provider.shouldFetchSubresources = false
        provider.timeout = timeout

        // `LPLinkMetadata` 不是 Sendable，只把标题字符串带回主线程
        provider.startFetchingMetadata(for: url) { metadata, _ in
            let title = metadata?.title

            Task { @MainActor in
                completionHandler(title)
            }
        }

        return {
            provider.cancel()
        }
    }
}
