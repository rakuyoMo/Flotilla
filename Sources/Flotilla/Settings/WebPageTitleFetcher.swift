import Foundation
import LinkPresentation

// MARK: - WebPageTitleFetcher

/// 用系统的 LinkPresentation 取网页的标题：“添加网页…” 的标题框留空时，自动带入网页的标题
///
/// 跳转、编码与 HTML 实体都由 LinkPresentation 处理
enum WebPageTitleFetcher {
    /// 开始取一个网址的标题，在主线程把结果交给 completionHandler；
    /// 失败、超时、被取消、网页没有标题，或标题只是网址里的文件名时为 nil
    ///
    /// 不隔离到主线程：LinkPresentation 在后台队列调用完成回调
    /// - Parameters:
    ///   - url: 网页的网址
    ///   - completionHandler: 在主线程收到网页的标题；标题本身原样，不去首尾空白
    /// - Returns: 取消这一次的闭包；取消之后 LinkPresentation 仍会调用完成回调，结果为 nil
    static func fetchTitle(
        of url: URL,
        completionHandler: @escaping @MainActor (String?) -> Void
    ) -> () -> Void {
        // 每个 provider 只能取一次
        let provider = LPMetadataProvider()

        // 只要标题：不下载图标、预览图等附带资源，实测（macOS 27）耗时约为默认的一半
        provider.shouldFetchSubresources = false

        // `LPLinkMetadata` 不是 Sendable：在后台队列读完、判断完，只把标题字符串带回主线程
        provider.startFetchingMetadata(for: url) { metadata, _ in
            // LinkPresentation 拿跳转之后的网址里的文件名充当标题
            let resolvedURL = metadata?.url ?? url

            let title = metadata?.title.flatMap {
                isFileName($0, of: resolvedURL) ? nil : $0
            }

            Task { @MainActor in
                completionHandler(title)
            }
        }

        return {
            provider.cancel()
        }
    }

    /// 标题是不是 LinkPresentation 拿网址里的文件名充当的：PDF、图片等不是网页的网址，
    /// 它以网址最后一段去掉扩展名作标题。它不公开内容类型，只能拿标题与网址比
    ///
    /// 大小写敏感，与 LinkPresentation 给出的一致：`/about` 的网页标题 “About” 不算；
    /// 网页自己的标题恰好与文件名相同时（`/Report.html` 的 “Report”）分辨不出，同样算
    /// - Parameters:
    ///   - title: LinkPresentation 给出的标题
    ///   - url: 跳转之后的网址，即 `LPLinkMetadata.url`
    static func isFileName(_ title: String, of url: URL) -> Bool {
        title == url.deletingPathExtension().lastPathComponent
    }
}
