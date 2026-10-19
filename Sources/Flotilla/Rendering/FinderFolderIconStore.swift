import AppKit
import QuickLookThumbnailing

// MARK: - FinderFolderIconStore

/// 组里访达文件夹的图标（需求 36、37）：按访达里的实际外观取图、缓存，外观变了随即重取
///
/// 面板的单元格、子组与 Dock 上 tile 的组图标、设置窗口的行都经这里取访达文件夹的图标。
/// 上了色、有 emoji 或符号的访达文件夹向 QuickLook 取系统画好的图标，其余的用 `NSWorkspace` 的图标。
/// 跟着组树监听全部层级里的访达文件夹，外观变了重新取图，取到后发出 `didUpdateIconNotification`；
/// 原路径上换了文件夹时，改为监听新的那个
@MainActor
final class FinderFolderIconStore {
    /// 一个访达文件夹取图结束，或取图超过 `loadingWaitLimit` 还没有结果时在主线程发出，
    /// `object` 为图标库，`userInfo` 的 `folderPathKey` 是文件夹的路径
    ///
    /// 换上了新图、退回 `NSWorkspace` 的图标、QuickLook 取不出来，都算取图结束
    nonisolated static let didUpdateIconNotification = Notification.Name(
        "FinderFolderIconStore.didUpdateIcon"
    )

    /// `didUpdateIconNotification` 的 `userInfo` 里文件夹路径的键，值是 `String`，与 `FileReference.url` 的路径写法相同
    nonisolated static let folderPathKey = "folderPath"

    /// App 使用的实例，跟着 `GroupStore.shared` 的组树
    static let shared = FinderFolderIconStore(store: .shared)

    /// 合并连续事件的间隔：改一次标签会在约 15 ms 内连着来几次属性变化
    private static let eventCoalescingInterval = Duration.milliseconds(200)

    /// 一次取图最多让 Dock 同步等多久：各档串行取图通常在 0.3 s 内结束，
    /// QuickLook 迟迟不回（如没有响应的网络卷）时，所有根组的同步不跟着一起卡住
    private static let loadingWaitLimit = Duration.seconds(2)

    /// 取图的各档尺寸：显示时取像素不少于所需的那张位图，都不放大
    ///
    /// QuickLook 出图的像素边长取不小于请求的标准档，如 20 pt × 1 → 24 px、101 pt × 2 → 256 px
    private nonisolated static let iconSizes: [(pointSize: CGFloat, scale: CGFloat)] = [
        // 设置窗口的行
        (20, 1),
        (20, 2),

        // 面板的单元格
        (GroupPanelMetrics.iconSize, 1),
        (GroupPanelMetrics.iconSize, 2),

        // Dock 上 tile 的预览格：512 pt 的画布 × 0.35，iconset 最大一档 1024 px 即 2 倍
        (512 * 0.35, 2),
    ]

    /// 图标的点尺寸，与 `NSWorkspace` 的图标相同；各处都按自己的边长绘制，取像素尺寸合适的那张位图
    private nonisolated static let iconPointSize = NSSize(width: 32, height: 32)

    /// 组树的唯一数据源：图标库跟着它监听访达文件夹
    private let store: GroupStore

    /// 取一个访达文件夹的图标：结果在任意线程交给回调，取不出时为 nil
    private let generateIcon: (URL, @escaping @Sendable (NSImage?) -> Void) -> Void

    /// 正在监听的访达文件夹，按路径
    private var watchers: [String: FinderFolderWatcher] = [:]

    /// 接上监听时各路径上文件夹的身份，按路径；那时路径上没有东西的没有这一项
    ///
    /// 收到事件、组树变化时与路径上现在的身份比较：路径上有东西、又对不上，就是换了文件夹，要重新接上监听
    private var identities: [String: FileIdentity] = [:]

    /// 各访达文件夹最近一次读到的外观，按路径；收到事件后与它比较，外观变了才重新取图
    private var appearances: [String: FinderFolderAppearance] = [:]

    /// 向 QuickLook 取到的图标与它的版本，按路径；没有的访达文件夹用 `NSWorkspace` 的图标
    private var icons: [String: (image: NSImage, version: Int)] = [:]

    /// 最近一张换进缓存的图标的版本：每换进一张新图加 1，各访达文件夹、各次换图的版本都不相同
    private var latestIconVersion = 0

    /// 还没有结果的取图，按路径：这次取图的编号，以及是否已超过 `loadingWaitLimit`
    ///
    /// 取图结束时移除；被更新的一次取图顶替后，旧的结果丢掉。超过上限的照常等结果，只是 Dock 同步不再等它
    private var iconLoads: [String: (id: UUID, isOverdue: Bool)] = [:]

    /// 收到事件后等着核对的任务，按路径；合并间隔内再来事件时取消并替换
    private var pendingChecks: [String: Task<Void, Never>] = [:]

    /// 对 “图标与小组件样式” 变化的观察
    private var iconStyleObservation: (any NSObjectProtocol)? = nil

    /// 对 App 外观的观察：App 没有固定外观，这个值跟随系统的深浅
    private var appearanceObservation: NSKeyValueObservation? = nil

    /// 向 QuickLook 取图的图标库
    /// - Parameter store: 组树的唯一数据源
    convenience init(store: GroupStore) {
        self.init(store: store) { url, completion in
            Self.quickLookIcon(of: url, completion: completion)
        }
    }

    /// 按给定的方法取图的图标库；测试里传入假实现
    /// - Parameters:
    ///   - store: 组树的唯一数据源
    ///   - generateIcon: 取一个访达文件夹的图标：结果在任意线程交给回调，取不出时为 nil
    init(
        store: GroupStore,
        generateIcon: @escaping (URL, @escaping @Sendable (NSImage?) -> Void) -> Void
    ) {
        self.store = store
        self.generateIcon = generateIcon
    }

    /// 访达文件夹在缓存与通知里用的路径：收到通知的各处据此认出是哪个访达文件夹
    /// - Parameter file: 组里的文件
    static func folderPath(of file: FileReference) -> String {
        file.url.path(percentEncoded: false)
    }

    /// 按当前的组树开始监听并取图，此后跟着组树增删监听，系统外观与图标样式变了全部重取
    ///
    /// macOS 26 之前访达不按标签上色，也没有 emoji 与符号：什么也不做，图标都是 `NSWorkspace` 的
    func start() {
        guard #available(macOS 26, *) else { return }

        updateWatchedFolders()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateWatchedFolders),
            name: GroupStore.didChangeNotification,
            object: store
        )

        // 样式或色调颜色变化时 AppKit 在 `NSWorkspace` 的通知中心发出这条通知
        iconStyleObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: AppIconController.iconAppearanceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reloadAllIcons()
            }
        }

        // 外观在主线程上变化，观察回调也在主线程；
        // 取 `NSApplication.shared` 而不是 `NSApp`：测试进程里不一定建过 App 对象，`NSApp` 可能还是 nil
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.reloadAllIcons()
            }
        }
    }

    /// 访达文件夹当前的图标：取到了 QuickLook 的图就用它，否则（没上色、换过自定义图标、还没取到、取不出）用 `FileReference.icon`
    ///
    /// 不是访达文件夹的文件同样给 `FileReference.icon`
    /// - Parameter file: 组里的文件
    func icon(of file: FileReference) -> NSImage {
        icons[Self.folderPath(of: file)]?.image ?? file.icon
    }

    /// 访达文件夹当前所用图标的版本：每换进一张 QuickLook 取到的新图就换一个，用 `FileReference.icon` 时为 nil
    ///
    /// 组图标的输入据此判断预览里的访达文件夹换没换图：外观变了、深浅外观或图标样式切换后重取，换进新图都换版本
    /// - Parameter file: 组里的文件
    func iconVersion(of file: FileReference) -> Int? {
        icons[Self.folderPath(of: file)]?.version
    }

    /// 访达文件夹是否还在取图：取完（含取不出）之前，Dock 同步要等它；取图超过 `loadingWaitLimit` 之后不再算
    /// - Parameter file: 组里的文件
    func isLoadingIcon(of file: FileReference) -> Bool {
        guard let load = iconLoads[Self.folderPath(of: file)] else { return false }

        return !load.isOverdue
    }

    /// 系统外观或图标样式变了：要用 QuickLook 的访达文件夹全部重取，旧图留到新图取到再换
    ///
    /// 由 `start()` 里的观察调用；测试里直接调用，模拟样式切换
    func reloadAllIcons() {
        #warning("TODO: 未能实测切换深浅外观与 “图标与小组件样式” 之后，QuickLook 马上重取的访达文件夹图标是否已是新的样子")

        for (path, appearance) in appearances where appearance.needsQuickLookIcon {
            loadIcon(atPath: path)
        }
    }
}

// MARK: - Watching

extension FinderFolderIconStore {
    /// 组树变化：按全部层级（含子组）里的访达文件夹增删监听；新加入的读出外观，要用 QuickLook 的随即取图；
    /// 已在监听的核对一次路径上的文件夹，换了的重新接上
    @objc
    private func updateWatchedFolders() {
        #warning("TODO: 未能实测 “文稿” “桌面” “下载” 等受保护位置里的访达文件夹，启动时读扩展属性与文件身份、查 `Icon\\r`、打开监听会不会比面板里第一次打开它更早弹出隐私授权框")

        let paths = finderFolderPaths(in: store.rootGroups.map { .group($0) })

        // 不在组树里的访达文件夹：停止监听，丢掉缓存；还没结束的取图随之作废
        for path in Set(appearances.keys).subtracting(paths) {
            watchers[path] = nil
            identities[path] = nil
            appearances[path] = nil
            icons[path] = nil
            iconLoads[path] = nil
            pendingChecks.removeValue(forKey: path)?.cancel()
        }

        // 已在监听的也核对一次：路径上原来没有文件夹（没有监听，收不到事件），
        // 或新文件夹放到原路径上晚于事件之后的那次核对时，靠这里发现
        let replacedPaths = paths
            .intersection(appearances.keys)
            .filter { path in
                // 路径上现在没有东西不算换了文件夹，理由同 `checkFolder(atPath:)`
                guard let identity = FileIdentity(path: path) else { return false }

                return identity != identities[path]
            }

        for path in replacedPaths {
            rewatchFolder(atPath: path)
        }

        for path in paths.subtracting(appearances.keys) {
            startWatching(atPath: path)
        }
    }

    /// 在一个路径上接上监听：记下路径上文件夹的身份，打开监听，读出外观；要用 QuickLook 的随即取图
    ///
    /// 先记身份、再打开：两步之间文件夹被换掉时，下一次核对身份对不上，重新接上，不会一直监听着被换走的那个
    /// - Parameter path: 访达文件夹的路径
    /// - Returns: 读到的外观
    @discardableResult
    private func startWatching(atPath path: String) -> FinderFolderAppearance {
        identities[path] = FileIdentity(path: path)

        // 文件夹打不开时没有监听，外观照样读：读不到的当作没有，用 `NSWorkspace` 的图标
        watchers[path] = FinderFolderWatcher(path: path) { [weak self] in
            self?.scheduleCheck(atPath: path)
        }

        let appearance = FinderFolderAppearance(folderAt: URL(filePath: path))
        appearances[path] = appearance

        if appearance.needsQuickLookIcon {
            loadIcon(atPath: path)
        }

        return appearance
    }

    /// 路径上换成了另一个文件夹（含接上监听时没有、现在有了）：丢掉旧的监听，在这个路径上重新接上、重读外观
    ///
    /// 要用 QuickLook 的重新取图，旧图留到新图取到再换；不用的丢掉旧图，退回 `NSWorkspace` 的图标
    /// - Parameter path: 访达文件夹的路径
    private func rewatchFolder(atPath path: String) {
        // 旧的监听绑定的是被换走的那个文件夹：先停掉，关掉描述符
        watchers[path] = nil

        guard !startWatching(atPath: path).needsQuickLookIcon else { return }

        dropIcon(atPath: path)
    }

    /// 文件夹有了事件：合并间隔之后核对这个路径，间隔内再来的事件并进同一次
    private func scheduleCheck(atPath path: String) {
        pendingChecks[path]?.cancel()
        pendingChecks[path] = Task { [weak self] in
            try? await Task.sleep(for: Self.eventCoalescingInterval)
            guard !Task.isCancelled else { return }

            self?.checkFolder(atPath: path)
        }
    }

    /// 核对一个路径：路径上换成了另一个文件夹就重新接上监听，还是原来那个就重读外观，没有东西就保持原样
    private func checkFolder(atPath path: String) {
        pendingChecks[path] = nil

        // 等待期间已从组树里拿掉
        guard let oldAppearance = appearances[path] else { return }

        // 路径上现在没有东西：文件夹被改名、挪走或删除，监听、外观与图都保持原样，不通知。
        // 组里这一项随后由 `GroupStore` 按书签跟到新位置，那时旧路径从组树里拿掉、新路径接上；
        // 按旧路径读出 “没有外观” 退回 `NSWorkspace` 的图标，Dock 会为改名白白多改写、多重启两次
        guard let identity = FileIdentity(path: path) else { return }

        // 原路径上已是另一个文件夹，之后的事件要从它那里来
        guard identity == identities[path] else {
            rewatchFolder(atPath: path)
            return
        }

        rereadAppearance(atPath: path, oldAppearance: oldAppearance)
    }

    /// 重读外观：没变（只是权限、时间戳等其它属性变了）就什么也不做；变了按新外观取图，或退回 `NSWorkspace` 的图标
    /// - Parameters:
    ///   - path: 访达文件夹的路径
    ///   - oldAppearance: 上一次读到的外观
    private func rereadAppearance(atPath path: String, oldAppearance: FinderFolderAppearance) {
        let appearance = FinderFolderAppearance(folderAt: URL(filePath: path))

        guard appearance != oldAppearance else { return }

        appearances[path] = appearance

        // 去掉了颜色与 emoji、符号，或换上了自定义图标
        guard appearance.needsQuickLookIcon else {
            dropIcon(atPath: path)
            return
        }

        // 旧图留到新图取到再换，期间仍按旧图显示
        loadIcon(atPath: path)
    }

    /// 全部层级里访达文件夹的路径，含子组里的
    ///
    /// 已在监听的路径上现在没有东西（文件夹被改名、挪走或删除）时照样算，保持原样，
    /// 等 `GroupStore` 按书签把这一项跟到新位置：`isFinderFolder` 对这样的路径给 false
    /// - Parameter items: 一个层级的项
    private func finderFolderPaths(in items: [GroupItem]) -> Set<String> {
        items.reduce(into: Set<String>()) {
            switch $1 {
            case .group(let group):
                $0.formUnion(finderFolderPaths(in: group.items))

            case .file(let file):
                let path = Self.folderPath(of: file)

                guard file.isFinderFolder || appearances[path] != nil else { return }

                $0.insert(path)

            default:
                break
            }
        }
    }
}

// MARK: - Loading

extension FinderFolderIconStore {
    /// 向 QuickLook 取一个访达文件夹的图标；结果回到主线程，换进缓存后发出通知
    ///
    /// 超过 `loadingWaitLimit` 还没有结果时，不再算作取图中，同样发出通知
    /// - Parameter path: 文件夹的路径
    private func loadIcon(atPath path: String) {
        let loadingID = UUID()
        iconLoads[path] = (loadingID, false)

        // 按路径新建 URL：同一个 URL 对象取过一次图后，改了标签再取，QuickLook 仍给旧颜色
        let url = URL(filePath: path, directoryHint: .isDirectory)

        generateIcon(url) { [weak self] image in
            Task { @MainActor in
                self?.finishLoading(
                    atPath: path,
                    loadingID: loadingID,
                    image: image
                )
            }
        }

        // 到了上限还没有结果：让推迟了的 Dock 同步按当前的图补上
        Task { [weak self] in
            try? await Task.sleep(for: Self.loadingWaitLimit)

            self?.stopWaiting(forLoadAtPath: path, loadingID: loadingID)
        }
    }

    /// 一次取图到了 `loadingWaitLimit` 还没有结果：不再算作取图中，发出通知；结果之后到了照常换上
    /// - Parameters:
    ///   - path: 文件夹的路径
    ///   - loadingID: 这次取图的编号
    private func stopWaiting(forLoadAtPath path: String, loadingID: UUID) {
        // 已有结果、被更新的一次取图顶替，或文件夹已从组树里拿掉：什么也不做
        guard iconLoads[path]?.id == loadingID else { return }

        iconLoads[path]?.isOverdue = true

        postIconUpdate(atPath: path)
    }

    /// 一次取图有了结果：取到了就换进缓存、换一个版本；取不出时，路径上还有东西就退回 `NSWorkspace` 的图标，
    /// 没有东西就保留已有的图与版本；都发出通知
    /// - Parameters:
    ///   - path: 文件夹的路径
    ///   - loadingID: 这次取图的编号
    ///   - image: 取到的图标；取不出时为 nil
    private func finishLoading(
        atPath path: String,
        loadingID: UUID,
        image: NSImage?
    ) {
        // 已被更新的一次取图顶替，或文件夹已从组树里拿掉：晚到的结果丢掉；只是超过了等待上限的照常换上
        guard iconLoads[path]?.id == loadingID else { return }

        iconLoads[path] = nil

        // 取不出是常态（文件夹刚被删除、没有权限），不记日志
        if let image {
            // 外观没变、只是重取（深浅外观或图标样式切换）时同样换版本：取到的图可能已经不同，交给 Dock 同步按像素比对
            latestIconVersion += 1
            icons[path] = (image, latestIconVersion)
        } else if FileIdentity(path: path) != nil {
            // 路径上有东西却取不出：退回 `NSWorkspace` 的图标。
            // 路径上没有东西（取图途中被改名、挪走或删除）时保留已有的图与版本，理由同 `checkFolder(atPath:)`
            icons[path] = nil
        }

        // 保留原样时同样通知：推迟了的 Dock 同步据此补上，输入没变，不重画
        postIconUpdate(atPath: path)
    }

    /// 访达文件夹不再用 QuickLook 取到的图：丢掉旧图，还没结束的取图作废，发出通知；之后用 `NSWorkspace` 的图标
    /// - Parameter path: 文件夹的路径
    private func dropIcon(atPath path: String) {
        icons[path] = nil
        iconLoads[path] = nil

        postIconUpdate(atPath: path)
    }

    /// 发出一个访达文件夹取图结束的通知
    private func postIconUpdate(atPath path: String) {
        NotificationCenter.default.post(
            name: Self.didUpdateIconNotification,
            object: self,
            userInfo: [Self.folderPathKey: path]
        )
    }
}

// MARK: - Helpers

extension FinderFolderIconStore {
    /// 向 QuickLook 依次取各档尺寸的 `.icon`，合成一张带全部位图的图标
    ///
    /// 不隔离到主线程：QuickLook 在自己的队列上调用完成回调
    /// - Parameters:
    ///   - url: 文件夹的 URL
    ///   - completion: 在 QuickLook 的队列上收到图标；任何一档取不出时为 nil
    private nonisolated static func quickLookIcon(
        of url: URL,
        completion: @escaping @Sendable (NSImage?) -> Void
    ) {
        quickLookBitmaps(of: url, sizes: iconSizes[...], collected: []) { bitmaps in
            guard let bitmaps else {
                completion(nil)
                return
            }

            let image = NSImage(size: iconPointSize)

            // 各张位图的点尺寸都设成图标的点尺寸，绘制时按像素密度挑出不小于所需的那张
            for bitmap in bitmaps {
                let representation = NSBitmapImageRep(cgImage: bitmap)
                representation.size = iconPointSize

                image.addRepresentation(representation)
            }

            completion(image)
        }
    }

    /// 依次取剩下各档尺寸的位图：上一档取到之后才请求下一档，取图的先后与各档的顺序一致
    /// - Parameters:
    ///   - url: 文件夹的 URL
    ///   - sizes: 还没取的各档尺寸
    ///   - collected: 已取到的位图
    ///   - completion: 全部取到时收到各档的位图，任何一档取不出时为 nil
    private nonisolated static func quickLookBitmaps(
        of url: URL,
        sizes: ArraySlice<(pointSize: CGFloat, scale: CGFloat)>,
        collected: [CGImage],
        completion: @escaping @Sendable ([CGImage]?) -> Void
    ) {
        guard let size = sizes.first else {
            completion(collected)
            return
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size.pointSize, height: size.pointSize),
            scale: size.scale,
            representationTypes: .icon
        )

        // 取 `cgImage` 而不是 `nsImage`：后者按 2 倍出图，1 倍的请求也给 2 倍的位图
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let bitmap = representation?.cgImage else {
                completion(nil)
                return
            }

            quickLookBitmaps(
                of: url,
                sizes: sizes.dropFirst(),
                collected: collected + [bitmap],
                completion: completion
            )
        }
    }
}
