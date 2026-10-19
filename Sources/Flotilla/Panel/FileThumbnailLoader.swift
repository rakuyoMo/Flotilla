import AppKit
import QuickLookThumbnailing

// MARK: - FileThumbnailLoader

/// 为访达文件夹的层级里的文件请求 QuickLook 内容缩略图：原生叠放里，文件显示的是内容缩略图而不是通用图标；
/// 上了色、有 emoji 或符号的子文件夹请求系统画好的文件夹图标（需求 38）
///
/// 缩略图在主线程交给调用方；`cancel(_:)` 取消一个还没完成的请求，`cancelAll()` 取消全部，之后到达的结果一律丢掉
@MainActor
final class FileThumbnailLoader {
    /// 生成一个文件的缩略图或图标：按请求的表示生成，结果在任意线程交给回调，生成不出时为 nil；返回取消这次请求的闭包
    private let generate: (
        URL,
        QLThumbnailGenerator.Request.RepresentationTypes,
        @escaping @Sendable (NSImage?) -> Void
    ) -> () -> Void

    /// 还没完成的请求：取消它的闭包，与拿到缩略图之后执行的回调
    private var pendingRequests: [UUID: (cancel: () -> Void, completion: (NSImage) -> Void)] = [:]

    /// 用 QuickLook 生成缩略图与图标
    /// - Parameter scale: 面板所在屏幕的倍数，缩略图与图标按它生成像素
    convenience init(scale: CGFloat) {
        self.init { url, representation, completion in
            Self.quickLookImage(
                of: url,
                representation: representation,
                scale: scale,
                completion: completion
            )
        }
    }

    /// 按给定的方法生成缩略图与图标；测试里传入假实现
    /// - Parameter generate: 生成一个文件的缩略图或图标：按请求的表示生成，结果在任意线程交给回调，生成不出时为 nil；
    ///   返回取消这次请求的闭包
    init(
        generate: @escaping (
            URL,
            QLThumbnailGenerator.Request.RepresentationTypes,
            @escaping @Sendable (NSImage?) -> Void
        ) -> () -> Void
    ) {
        self.generate = generate
    }

    /// 请求一个文件的缩略图或图标；生成出来、请求又没被取消时，在主线程交给 `completion`
    /// - Parameters:
    ///   - url: 文件的 URL
    ///   - representation: `.thumbnail` 要内容缩略图，放进 100 pt 的画布居中；`.icon` 要系统画好的图标，画满 101 pt 的图标画布
    ///   - completion: 拿到缩略图或图标之后执行；生成不出、请求被取消时不执行
    /// - Returns: 这次请求的编号，交给 `cancel(_:)` 取消它
    func loadThumbnail(
        of url: URL,
        representation: QLThumbnailGenerator.Request.RepresentationTypes,
        completion: @escaping (NSImage) -> Void
    ) -> UUID {
        let id = UUID()

        // 结果可能在任意线程到达：回到主线程，再按请求是否还在决定用不用
        let cancel = generate(url, representation) { [weak self] thumbnail in
            Task { @MainActor in
                self?.finishRequest(id, thumbnail: thumbnail)
            }
        }

        pendingRequests[id] = (cancel, completion)

        return id
    }

    /// 取消一个还没完成的请求：QuickLook 按先后生成，取消后不再占着队列；之后到达的结果丢掉
    ///
    /// 请求已完成或已取消时什么也不做
    /// - Parameter id: `loadThumbnail(of:representation:completion:)` 返回的编号
    func cancel(_ id: UUID) {
        pendingRequests.removeValue(forKey: id)?.cancel()
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

        // 生成不出缩略图是常态（访达文件夹、没有缩略图扩展的类型、已删除、没有权限），
        // 保持图标，不记日志
        guard let thumbnail else { return }

        request.completion(thumbnail)
    }
}

// MARK: - Helpers

extension FileThumbnailLoader {
    /// 用 QuickLook 生成一个文件在网格里显示的图：内容缩略图与原生叠放相同，放进网格的图标画布；图标画满图标画布
    ///
    /// 不隔离到主线程：QuickLook 在自己的队列上调用完成回调
    /// - Parameters:
    ///   - url: 文件的 URL
    ///   - representation: `.thumbnail` 或 `.icon`
    ///   - scale: 屏幕的倍数
    ///   - completion: 在 QuickLook 的队列上收到缩略图或图标，生成不出时为 nil
    /// - Returns: 取消这次请求的闭包
    private nonisolated static func quickLookImage(
        of url: URL,
        representation: QLThumbnailGenerator.Request.RepresentationTypes,
        scale: CGFloat,
        completion: @escaping @Sendable (NSImage?) -> Void
    ) -> () -> Void {
        guard representation == .thumbnail else {
            return quickLookIcon(of: url, scale: scale, completion: completion)
        }

        let side = GroupPanelMetrics.fileThumbnailSize

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .thumbnail
        )

        // 图标模式：内容画成带圆角、1 pt 亮边与纯黑投影的页面或图片，即访达图标视图的 “显示图标预览”。
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

    /// 用 QuickLook 生成系统画好的文件夹图标：上了色、有 emoji 或符号的访达文件夹，`NSWorkspace` 的图标里没有这些
    ///
    /// 不隔离到主线程：QuickLook 在自己的队列上调用完成回调
    /// - Parameters:
    ///   - url: 文件夹的 URL
    ///   - scale: 屏幕的倍数
    ///   - completion: 在 QuickLook 的队列上收到图标，生成不出时为 nil
    /// - Returns: 取消这次请求的闭包
    private nonisolated static func quickLookIcon(
        of url: URL,
        scale: CGFloat,
        completion: @escaping @Sendable (NSImage?) -> Void
    ) -> () -> Void {
        let side = GroupPanelMetrics.iconSize

        // 按路径新建 URL：同一个 URL 对象取过一次图后，改了标签再取，QuickLook 仍给旧颜色
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(filePath: url.path(percentEncoded: false), directoryHint: .isDirectory),
            size: CGSize(width: side, height: side),
            scale: scale,
            representationTypes: .icon
        )

        // 图标与其它格的图标一样画满图标画布，不像缩略图那样居中留边；
        // 取 `cgImage` 而不是 `nsImage`：后者按 2 倍出图，1 倍屏也给 2 倍的位图
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            completion(representation.map {
                NSImage(cgImage: $0.cgImage, size: CGSize(width: side, height: side))
            })
        }

        return {
            QLThumbnailGenerator.shared.cancel(request)
        }
    }

    /// 把缩略图居中放进网格的图标画布
    ///
    /// 单元格把图标缩放到图标画布的大小显示；缩略图的画布比图标画布小，先居中放进去，才按原样大小显示，中心与图标相同
    private nonisolated static func centeredInIconCanvas(_ thumbnail: NSImage) -> NSImage {
        let canvas = GroupPanelMetrics.iconSize
        let inset = (canvas - GroupPanelMetrics.fileThumbnailSize) / 2

        return NSImage(size: CGSize(width: canvas, height: canvas), flipped: false) { rect in
            thumbnail.draw(in: rect.insetBy(dx: inset, dy: inset))

            return true
        }
    }
}
