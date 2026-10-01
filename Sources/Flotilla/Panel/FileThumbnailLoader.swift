import AppKit
import QuickLookThumbnailing

// MARK: - FileThumbnailLoader

/// 为访达里的文件夹的层级里的文件请求 QuickLook 内容缩略图：原生叠放里，文件显示的是内容缩略图而不是通用图标
///
/// 缩略图在主线程交给调用方；`cancelAll()` 取消还没完成的请求，之后到达的结果一律丢掉
@MainActor
final class FileThumbnailLoader {
    /// 生成一个文件的缩略图：结果在任意线程交给回调，生成不出时为 nil；返回取消这次请求的闭包
    private let generate: (URL, @escaping @Sendable (NSImage?) -> Void) -> () -> Void

    /// 还没完成的请求：取消它的闭包，与拿到缩略图之后执行的回调
    private var pendingRequests: [UUID: (cancel: () -> Void, completion: (NSImage) -> Void)] = [:]

    /// 用 QuickLook 生成缩略图
    /// - Parameter scale: 面板所在屏幕的倍数，缩略图按它生成像素
    convenience init(scale: CGFloat) {
        self.init { url, completion in
            Self.quickLookThumbnail(of: url, scale: scale, completion: completion)
        }
    }

    /// 按给定的方法生成缩略图；测试里传入假实现
    /// - Parameter generate: 生成一个文件的缩略图：结果在任意线程交给回调，生成不出时为 nil；返回取消这次请求的闭包
    init(
        generate: @escaping (URL, @escaping @Sendable (NSImage?) -> Void) -> () -> Void
    ) {
        self.generate = generate
    }

    /// 请求一个文件的缩略图；生成出来、请求又没被取消时，在主线程把缩略图交给 `completion`
    /// - Parameters:
    ///   - url: 文件的 URL
    ///   - completion: 拿到缩略图之后执行；生成不出、请求被取消时不执行
    func loadThumbnail(of url: URL, completion: @escaping (NSImage) -> Void) {
        let id = UUID()

        // 结果可能在任意线程到达：回到主线程，再按请求是否还在决定用不用
        let cancel = generate(url) { [weak self] thumbnail in
            Task { @MainActor in
                self?.finishRequest(id, thumbnail: thumbnail)
            }
        }

        pendingRequests[id] = (cancel, completion)
    }

    /// 取消全部还没完成的请求，不再占用 QuickLook；之后到达的结果丢掉
    func cancelAll() {
        for request in pendingRequests.values {
            request.cancel()
        }

        pendingRequests = [:]
    }
}

// MARK: - Private

extension FileThumbnailLoader {
    /// 一个请求有了结果：生成出缩略图时交给回调
    /// - Parameters:
    ///   - id: 请求的编号
    ///   - thumbnail: 缩略图；生成不出时为 nil
    private func finishRequest(_ id: UUID, thumbnail: NSImage?) {
        // 已取消的请求不在表里：晚到的结果丢掉，不会落到已离开的层级上
        guard let request = pendingRequests.removeValue(forKey: id) else { return }

        // 生成不出缩略图是常态（子目录、没有缩略图扩展的类型、已删除、没有权限），保持图标，不记日志
        guard let thumbnail else { return }

        request.completion(thumbnail)
    }
}

// MARK: - Helpers

extension FileThumbnailLoader {
    /// 用 QuickLook 生成一个文件的缩略图，与原生叠放相同，并放进网格的图标画布
    ///
    /// 不隔离到主线程：QuickLook 在自己的队列上调用完成回调
    /// - Parameters:
    ///   - url: 文件的 URL
    ///   - scale: 屏幕的倍数
    ///   - completion: 在 QuickLook 的队列上收到缩略图，生成不出时为 nil
    /// - Returns: 取消这次请求的闭包
    private nonisolated static func quickLookThumbnail(
        of url: URL,
        scale: CGFloat,
        completion: @escaping @Sendable (NSImage?) -> Void
    ) -> () -> Void {
        let side = FolderPanelMetrics.fileThumbnailSize

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .thumbnail
        )

        // 图标模式：内容画成带圆角、1 pt 亮边与纯黑投影的页面或图片，即访达图标视图的“显示图标预览”。
        // 投影纯黑，按下时单元格把图乘以 0.475，投影保持不变，与原生相同
        request.iconMode = true

        // 只取出图，不把 QuickLook 的结果对象带出它的队列
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            completion(representation.map { centeredInIconCanvas($0.nsImage) })
        }

        return {
            QLThumbnailGenerator.shared.cancel(request)
        }
    }

    /// 把缩略图居中放进网格的图标画布
    ///
    /// 单元格把图标缩放到图标画布的大小显示；缩略图的画布比图标画布小，先居中放进去，才按原样大小显示，中心与图标相同
    private nonisolated static func centeredInIconCanvas(_ thumbnail: NSImage) -> NSImage {
        let canvas = FolderPanelMetrics.iconSize
        let inset = (canvas - FolderPanelMetrics.fileThumbnailSize) / 2

        return NSImage(size: CGSize(width: canvas, height: canvas), flipped: false) { rect in
            thumbnail.draw(in: rect.insetBy(dx: inset, dy: inset))

            return true
        }
    }
}
