import AppKit
import os
import QuartzCore

// MARK: - GroupPanelController

/// 管理全局唯一的面板：按 tile 摆放、构建每个层级、嵌套导航（需求 1）与访达文件夹的展开（需求 20），
/// 以及展开、收起与转场动画
///
/// 每个层级是一个 `GroupPanelLevel`，四周带着阴影留白；窗口 frame 是当前全部层级的并集。
/// 展开与收起只对 contentView 图层的 transform 与 opacity 做动画，锚点在 tile 图标中心
@MainActor
final class GroupPanelController {
    /// 面板相关的日志
    private nonisolated static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "GroupPanelController"
    )

    /// 面板窗口；`DockGroupPresenter` 据此认出落在面板里的鼠标按下
    let panel = GroupPanel()

    /// 请求收起面板：由 `DockGroupPresenter` 更新状态并收起；
    /// 按下 Esc，点击 App、文件、网页或 “在访达中打开”，以及要进入或返回的那一层读不出来时调用
    var dismissRequestHandler: (() -> Void)? = nil

    /// 本次展开里各次读访达文件夹占住主线程的时段，`DockGroupPresenter` 据此忽略这期间的鼠标按下
    private(set) var readPeriods = FinderFolderReadPeriods()

    /// 面板的 contentView，承载全部层级；展开与收起的动画作用在它的图层上
    private let containerView = NSView()

    /// 组树的唯一数据源
    private let store: GroupStore

    /// 用户设置，决定子组图标里的预览数量，以及访达文件夹是否显示隐藏文件
    private let preferences: Preferences

    /// 本次展开的定位依据
    private var anchor: DockTileAnchor? = nil

    /// 展开、收起时整个面板缩放的锚点（tile 图标中心），AppKit 屏幕坐标
    private var scaleAnchor = CGPoint.zero

    /// 从根组到当前层级的各层 id：根组、子组或访达文件夹
    private var path: [UUID] = []

    /// 当前层级：正在显示、接收点击的那一层；面板收起后为 nil
    private var currentLevel: GroupPanelLevel? = nil

    /// 转场中正在淡出、缩走的层级，动画结束后移除
    private var departingLevels: [GroupPanelLevel] = []

    /// 本次展开中各层级网格的滚动位置，按层级的 id 记录，返回上一层时恢复
    private var scrollOffsets: [UUID: CGPoint] = [:]

    /// 本次展开里读出的访达文件夹的内容，让其中各项的 id 在这一次展开里保持不变
    private var finderFolderContents = FinderFolderContents()

    /// 动画代数：每次立即隐藏、开始收起都加一，过期的收起收尾据此放弃
    private var animationGeneration = 0

    /// 展开期间跟踪鼠标移动的监听，决定点击是否穿透面板
    private var mouseMonitors: [Any] = []

    /// 创建面板控制器
    /// - Parameters:
    ///   - store: 组树的唯一数据源
    ///   - preferences: 用户设置，决定子组图标里的预览数量，以及访达文件夹是否显示隐藏文件
    init(store: GroupStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences

        containerView.wantsLayer = true
        panel.contentView = containerView

        panel.cancelHandler = { [weak self] in
            self?.dismissRequestHandler?()
        }
    }

    /// 沿导航路径逐层查找，返回当前层级的内容：在当前层的项里找下一层的 id，子组取它本身，访达文件夹读出目录
    /// - Parameters:
    ///   - path: 从根组到当前层级的各层 id
    ///   - rootGroups: 组树的根组
    ///   - finderFolderItems: 读出访达文件夹里的各项；读不出来时为 nil
    /// - Returns: 根组已不是根组、路径上任何一层已不在上一层之内、或某一层读不出来时为 nil
    static func levelContent(
        at path: [UUID],
        in rootGroups: [Group],
        finderFolderItems: (FileReference) -> [GroupItem]?
    ) -> GroupPanelLevelContent? {
        guard
            let rootID = path.first,
            let rootGroup = rootGroups.first(where: { $0.id == rootID })
        else {
            return nil
        }

        var content = GroupPanelLevelContent.group(rootGroup)

        for levelID in path.dropFirst() {
            guard let item = content.items.first(where: { $0.id == levelID }) else { return nil }

            switch item {
            case .group(let subgroup):
                content = .group(subgroup)

            // 访达文件夹按它当前的 URL 读，它可能刚按书签跟到新位置
            case .file(let finderFolder) where finderFolder.isFinderFolder:
                guard let items = finderFolderItems(finderFolder) else { return nil }

                content = .finderFolder(finderFolder, items: items)

            // 已不再是访达文件夹，或是 App、网页：进不去
            default:
                return nil
            }
        }

        return content
    }

    /// 一个层级交给网格的拖动判定与动作：只有组的层级有，访达文件夹的层级为 nil
    ///
    /// 网格交出的目标格是移动之后的下标，按建这一层时的各项换算成 `GroupStore.move(itemID:to:at:)` 的下标
    /// - Parameters:
    ///   - content: 这一层展示的内容
    ///   - store: 保存新的顺序、删除这一项的数据源
    ///   - containsScreenPoint: 屏幕上的点是否在当前层级的轮廓之内
    ///   - removeBoundaryContainsScreenPoint: 屏幕上的点是否在当前层级 “移除” 的边界之内
    ///   - releaseHandler: 松开时执行：按鼠标当时的位置更新点击穿透
    static func dragActions(
        for content: GroupPanelLevelContent,
        in store: GroupStore,
        containsScreenPoint: @escaping @MainActor (CGPoint) -> Bool,
        removeBoundaryContainsScreenPoint: @escaping @MainActor (CGPoint) -> Bool,
        releaseHandler: @escaping @MainActor () -> Void
    ) -> GroupGridDragActions? {
        guard case .group(let group) = content else { return nil }

        return GroupGridDragActions(
            containsScreenPoint: containsScreenPoint,
            removeBoundaryContainsScreenPoint: removeBoundaryContainsScreenPoint,
            releaseHandler: releaseHandler,
            moveHandler: { item, targetIndex in
                let sourceIndex = group.items.firstIndex { $0.id == item.id }

                guard let sourceIndex else { return }

                store.move(
                    itemID: item.id,
                    to: group.id,
                    at: GroupGridDragArrangement.moveIndex(from: sourceIndex, to: targetIndex)
                )
            },
            removeHandler: {
                // 删的只是组里的这一项，不动磁盘上的 App 与文件；子组连同其中的内容一起删除，不弹确认
                store.remove(itemID: $0.id)
            }
        )
    }
}

// MARK: - Presenting

extension GroupPanelController {
    /// 展开根组的根层级；已有面板时旧面板立即消失，新面板按展开动画出现
    func expand(rootGroup: Group, anchor: DockTileAnchor) {
        hideImmediately()

        self.anchor = anchor
        path = [rootGroup.id]

        let (level, placement) = makeLevel(for: .group(rootGroup), anchor: anchor)
        scaleAnchor = placement.anchor
        install(level)

        // 先装好动画再显示，第一帧就是收起的画面；
        // 用 `orderFrontRegardless()` 显示、`makeKey()` 接收 Esc，都不激活 Flotilla（需求 6）
        animateExpansion()
        panel.orderFrontRegardless()
        panel.makeKey()

        startTrackingMouse()
        updateMousePassthrough()
    }

    /// 按收起动画收起面板；打断进行中的展开时从当前画面开始收起
    func collapse() {
        guard panel.isVisible, let layer = containerView.layer else { return }

        // 进行中的拖动立即作废，拖动图像不等收起动画结束就消失
        currentLevel?.gridView?.cancelDrag()

        animationGeneration += 1
        let generation = animationGeneration

        // 收起一开始就让点击全部穿透，面板不再挡住下面的窗口
        stopTrackingMouse()
        panel.ignoresMouseEvents = true

        animateCollapse(of: layer)

        // 收起期间又有新的展开或收起时，这次的收尾作废
        afterAnimation(GroupPanelMetrics.collapseDuration) { [weak self] in
            guard let self, generation == animationGeneration else { return }

            hideImmediately()
        }
    }

    /// 组树变化后按新数据重建当前层级，保留滚动位置，不带动画；访达文件夹的层级重新读取
    /// - Returns: 当前层级已不在该根组之下、或某一层读不出来时为 false，由调用方收起面板
    func reload() -> Bool {
        guard
            let anchor,
            let content = currentPathContent()
        else {
            return false
        }

        if let currentLevel {
            saveScrollOffset(of: currentLevel)
        }

        // 转场中的层级一并丢弃，只留下按新数据重建的当前层级
        removeAllLevels()
        install(makeLevel(for: content, anchor: anchor).level)
        updateMousePassthrough()

        return true
    }
}

// MARK: - Navigation

extension GroupPanelController {
    /// 点击网格中的一项：
    /// App 直接启动、文件用默认 App 打开、网页用默认浏览器打开，随即收起面板（需求 9、14）；
    /// 子组与访达文件夹在同一个面板里进入
    private func select(_ item: GroupItem) {
        switch item {
        case .app(let app):
            launch(app)

        case .group(let group):
            enter(.group(group))

        // 点击时才判断是不是访达文件夹：文件包、符号链接、替身与已删除的都按文件打开
        case .file(let file) where file.isFinderFolder:
            enter(finderFolder: file)

        case .file(let file):
            open(file.url, named: file.displayName)

        case .webPage(let webPage):
            open(webPage.url, named: webPage.displayName)
        }
    }

    /// 进入访达文件夹：读出目录里的各项再进入；读不出来时交给访达打开，随即收起面板
    private func enter(finderFolder: FileReference) {
        let items: [GroupItem]

        do {
            items = try readItems(of: finderFolder)
        } catch {
            Self.logger.error(
                "读取 \(finderFolder.displayName, privacy: .public) 的内容失败：\(error.localizedDescription, privacy: .public)"
            )

            open(finderFolder.url, named: finderFolder.displayName)
            return
        }

        enter(.finderFolder(finderFolder, items: items))
    }

    /// 进入子组或访达文件夹：新层级从被点击的图标里长出来，旧层级原地淡出
    private func enter(_ content: GroupPanelLevelContent) {
        guard
            let anchor,
            let parent = currentLevel,
            let iconCenter = parent.iconCenterOnScreen(of: content.id)
        else {
            return
        }

        saveScrollOffset(of: parent)
        path.append(content.id)

        // 新层级叠在旧层级之上，旧层级转入淡出队列
        let level = makeLevel(for: content, anchor: anchor).level
        departingLevels.append(parent)
        install(level)
        updateMousePassthrough()

        animateEntrance(of: level, from: iconCenter)
        fadeOut(parent)
    }

    /// 返回上一层：当前层级缩回父层级里它的图标并淡出，父层级原地淡入；上一层已不存在或读不出来时收起面板
    private func goBack() {
        guard
            let anchor,
            let child = currentLevel,
            path.count > 1
        else {
            return
        }

        path.removeLast()

        guard let parentContent = currentPathContent() else {
            dismissRequestHandler?()
            return
        }

        // 父层级按记下的滚动位置重建，放在子层级下面
        let parent = makeLevel(for: parentContent, anchor: anchor).level
        departingLevels.append(child)
        install(parent, below: child.view)
        updateMousePassthrough()

        animateReturn(of: child, to: parent.iconCenterOnScreen(of: child.id))
        fadeIn(parent)
    }

    /// 启动 App，随即请求收起面板
    private func launch(_ app: AppReference) {
        let name = app.displayName

        NSWorkspace.shared.openApplication(
            at: app.url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            guard let error else { return }

            Self.logger.error(
                "启动 \(name, privacy: .public) 失败：\(error.localizedDescription, privacy: .public)"
            )
        }

        dismissRequestHandler?()
    }

    /// 用默认 App 打开文件或网页，随即请求收起面板
    /// - Parameters:
    ///   - url: 文件 URL 或网址
    ///   - name: 显示名，只用于日志
    private func open(_ url: URL, named name: String) {
        // 打开失败时系统按 `OpenConfiguration` 的默认设置提示用户，例如文件已不在时弹出 “找不到”；
        // 这里另记日志，面板照常收起
        NSWorkspace.shared.open(
            url,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            guard let error else { return }

            Self.logger.error(
                "打开 \(name, privacy: .public) 失败：\(error.localizedDescription, privacy: .public)"
            )
        }

        dismissRequestHandler?()
    }
}

// MARK: - Levels

extension GroupPanelController {
    /// 构建一个层级：背景、标题区与网格，并按 tile 算出它在屏幕上的位置
    /// - Returns: 层级，以及算出它位置的 `GroupPanelPlacement`
    private func makeLevel(
        for content: GroupPanelLevelContent,
        anchor: DockTileAnchor
    ) -> (level: GroupPanelLevel, placement: GroupPanelPlacement) {
        let visibleFrame = anchor.screen.visibleFrame

        // 网格的列数与显示行数受 tile 旁可用的空间限制；访达文件夹多出 “在访达中打开” 一格
        let layout = GroupGridLayout(
            itemCount: content.cellCount,
            availableSize: GroupPanelPlacement.availableBodySize(
                tileFrame: anchor.tileFrame,
                edge: anchor.edge,
                visibleFrame: visibleFrame
            )
        )

        let placement = GroupPanelPlacement(
            bodySize: layout.bodySize,
            tileFrame: anchor.tileFrame,
            edge: anchor.edge,
            visibleFrame: visibleFrame,
            scale: anchor.screen.backingScaleFactor
        )

        // 视图是轮廓（主体加尾巴尖端）的外接矩形四周再扩出阴影留白，同时盖住 tile 图标中心的缩放锚点
        let margin = GroupPanelMetrics.shadowMargin
        let screenFrame = placement.bodyFrame
            .union(CGRect(origin: placement.tailTip, size: .zero))
            .insetBy(dx: -margin, dy: -margin)
        let origin = screenFrame.origin

        let view = GroupPanelBackgroundView(
            frame: CGRect(origin: .zero, size: screenFrame.size),
            bodyRect: placement.bodyFrame.offsetBy(dx: -origin.x, dy: -origin.y),
            tailTip: CGPoint(
                x: placement.tailTip.x - origin.x,
                y: placement.tailTip.y - origin.y
            ),
            edge: anchor.edge
        )

        view.bodyView.addSubview(makeHeader(title: content.title, bodySize: layout.bodySize))

        // 空的组只有标题区，格内为空；空的访达文件夹仍有 “在访达中打开” 一格
        let scrollView = content.cellCount == 0
            ? nil
            : makeScrollView(
                for: content,
                layout: layout,
                scale: anchor.screen.backingScaleFactor
            )

        if let scrollView {
            view.bodyView.addSubview(scrollView)
        }

        let level = GroupPanelLevel(
            id: content.id,
            view: view,
            screenFrame: screenFrame,
            dockEdge: anchor.edge,
            dockScreenFrame: anchor.screen.frame,
            scrollView: scrollView,
            gridView: scrollView?.documentView as? GroupGridView
        )

        return (level, placement)
    }

    /// 标题区：占面板主体顶部，子层级带返回按钮
    private func makeHeader(
        title: String,
        bodySize: CGSize
    ) -> GroupNavigationHeaderView {
        let backHandler: (() -> Void)? = path.count > 1
            ? { [weak self] in self?.goBack() }
            : nil

        let header = GroupNavigationHeaderView(title: title, backHandler: backHandler)
        let height = GroupPanelMetrics.headerHeight

        header.frame = CGRect(
            x: 0,
            y: bodySize.height - height,
            width: bodySize.width,
            height: height
        )

        return header
    }

    /// 网格所在的滚动视图：向右伸进主体右侧的留白，overlay 滚动条落在留白里；恢复这一层上次的滚动位置
    /// - Parameters:
    ///   - content: 这一层展示的内容
    ///   - layout: 按格数算好的布局
    ///   - scale: 面板所在屏幕的倍数，文件的内容缩略图按它生成
    private func makeScrollView(
        for content: GroupPanelLevelContent,
        layout: GroupGridLayout,
        scale: CGFloat
    ) -> NSScrollView {
        let cell = GroupPanelMetrics.cellSize
        let sideInset = GroupPanelMetrics.gridSideInset

        let scrollView = NSScrollView(frame: CGRect(
            x: sideInset,
            y: GroupPanelMetrics.gridBottomInset,
            width: layout.gridSize.width + sideInset - GroupPanelMetrics.scrollerTrailingInset,
            height: CGFloat(layout.visibleRowCount) * cell
        ))

        // 只在行数超出显示行数时垂直滚动；放得下时关掉回弹
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = layout.needsScrolling
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = layout.needsScrolling ? .automatic : .none
        scrollView.horizontalScrollElasticity = .none

        // “在访达中打开” 由访达打开这一层的目录，随即收起面板
        let openInFinderHandler: (() -> Void)? = content.finderFolderURL.map { url in
            { [weak self] in self?.open(url, named: content.title) }
        }

        // 访达文件夹的层级里，文件按原生叠放显示内容缩略图
        let fileThumbnailLoader = content.showsFileThumbnails
            ? FileThumbnailLoader(scale: scale)
            : nil

        // 组的层级里各项可以拖动：鼠标是否在轮廓之内、是否在 “移除” 的边界之内，都按当前层级判定；
        // 松开时按鼠标的位置更新点击穿透，不等鼠标下一次移动
        let dragActions = Self.dragActions(
            for: content,
            in: store,
            containsScreenPoint: { [weak self] in
                self?.currentLevel?.contains(screenPoint: $0) ?? false
            },
            removeBoundaryContainsScreenPoint: { [weak self] in
                self?.currentLevel?.removeBoundaryContains(screenPoint: $0) ?? false
            },
            releaseHandler: { [weak self] in
                self?.updateMousePassthrough()
            }
        )

        // 隐藏的项只来自访达文件夹：本次展开读出的隐藏项按 id 交给网格，组里各项的 id 不在其中
        scrollView.documentView = GroupGridView(
            items: content.items,
            layout: layout,
            previewIconCount: preferences.previewIconCount,
            hiddenItemIDs: finderFolderContents.hiddenItemIDs,
            fileThumbnailLoader: fileThumbnailLoader,
            openInFinderHandler: openInFinderHandler,
            dragActions: dragActions
        ) { [weak self] in
            self?.select($0)
        }

        if let offset = scrollOffsets[content.id] {
            scrollView.contentView.scroll(to: offset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        return scrollView
    }

    /// 把层级设为当前层级并放进面板
    /// - Parameters:
    ///   - level: 新的当前层级
    ///   - sibling: 不为 nil 时放在它下面，否则放在最上面
    private func install(_ level: GroupPanelLevel, below sibling: NSView? = nil) {
        containerView.addSubview(
            level.view,
            positioned: sibling == nil ? .above : .below,
            relativeTo: sibling
        )

        currentLevel = level

        fitWindow()
    }

    /// 窗口 frame 设为全部层级的并集，再按新的窗口原点摆放每个层级，层级在屏幕上的位置保持不变
    private func fitWindow() {
        let levels = departingLevels + [currentLevel].compactMap(\.self)

        let frame: CGRect? = levels
            .map(\.screenFrame)
            .reduce(nil) { $0?.union($1) ?? $1 }

        guard let frame else { return }

        panel.setFrame(frame, display: false)

        // AppKit 会把窗口原点取整到整数 pt，层级按取整后的实际原点摆放，内容才留在算出的屏幕位置
        let origin = panel.frame.origin

        for level in levels {
            level.view.frame = level.screenFrame.offsetBy(dx: -origin.x, dy: -origin.y)
        }
    }

    /// 转场结束后移除离开的层级，窗口收缩到剩下的层级
    ///
    /// 移除之前窗口一直是全部层级的并集，转场途中越出剩下层级范围的画面靠它才不被窗口边界裁掉，因此 delay 取整个转场的时长
    /// - Parameters:
    ///   - level: 离开的层级
    ///   - delay: 转场的时长
    private func removeDepartingLevel(
        _ level: GroupPanelLevel,
        after delay: CFTimeInterval
    ) {
        afterAnimation(delay) { [weak self] in
            guard
                let self,
                let index = departingLevels.firstIndex(where: { $0.view === level.view })
            else {
                return
            }

            departingLevels.remove(at: index)
            level.view.removeFromSuperview()
            fitWindow()
        }
    }

    /// 移除全部层级：当前层级与转场中的层级都从面板里拿掉，当前层级置为 nil
    private func removeAllLevels() {
        for level in departingLevels + [currentLevel].compactMap(\.self) {
            level.view.removeFromSuperview()
        }

        departingLevels = []
        currentLevel = nil
    }

    /// 按当前的导航路径与组树解析出当前层级的内容；访达文件夹的层级重新读取
    private func currentPathContent() -> GroupPanelLevelContent? {
        Self.levelContent(at: path, in: store.rootGroups) {
            try? readItems(of: $0)
        }
    }

    /// 读出访达文件夹里的各项，并记下这次读取占住主线程的时段
    ///
    /// 第一次读受保护的位置时读取等到用户回答隐私授权框，这期间的鼠标按下要据此认出来
    /// - Throws: 读不出内容时抛出：已删除、没有权限、隐私授权被拒
    private func readItems(of finderFolder: FileReference) throws -> [GroupItem] {
        let start = ProcessInfo.processInfo.systemUptime

        // 读取成功、失败都记下：授权框被拒时，点 “不允许” 的按下同样排在读取之后才处理
        defer {
            readPeriods.record(start ... ProcessInfo.processInfo.systemUptime)
        }

        // 是否显示隐藏文件按读取当时的设置：切换设置要点设置窗口，面板这时已经收起
        return try finderFolderContents.items(
            of: finderFolder,
            includingHiddenFiles: preferences.showsHiddenFiles
        )
    }

    /// 记下层级网格当前的滚动位置
    private func saveScrollOffset(of level: GroupPanelLevel) {
        guard let scrollView = level.scrollView else { return }

        scrollOffsets[level.id] = scrollView.contentView.bounds.origin
    }

    /// 立即隐藏面板，丢弃进行中的动画与全部层级
    private func hideImmediately() {
        animationGeneration += 1

        stopTrackingMouse()
        containerView.layer?.removeAllAnimations()
        panel.orderOut(nil)

        removeAllLevels()
        path = []
        anchor = nil
        scrollOffsets = [:]
        finderFolderContents = FinderFolderContents()
        readPeriods = FinderFolderReadPeriods()
    }
}

// MARK: - Mouse Passthrough

extension GroupPanelController {
    /// 开始跟踪鼠标移动：窗口比轮廓大得多（阴影留白、盖住 tile 的锚点延伸），轮廓以外的点击要穿透到下面
    ///
    /// 鼠标移动时更新，拖动期间保持不变，按下的格子才收得到抬起；
    /// 拖动松开时由网格另外更新一次（`GroupGridDragActions.releaseHandler`）
    private func startTrackingMouse() {
        guard mouseMonitors.isEmpty else { return }

        // 鼠标不在面板上时移动事件发往其它 App，在面板上时发往面板自己
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .mouseMoved
        ) { [weak self] _ in
            self?.updateMousePassthrough()
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .mouseMoved
        ) { [weak self] event in
            self?.updateMousePassthrough()

            return event
        }

        mouseMonitors = [globalMonitor, localMonitor].compactMap(\.self)
    }

    /// 停止跟踪鼠标移动：移除展开时装上的两个监听
    private func stopTrackingMouse() {
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }

        mouseMonitors = []
    }

    /// 鼠标在当前层级的轮廓之内时面板接收点击，否则点击穿透
    private func updateMousePassthrough() {
        let isInside = currentLevel?.contains(screenPoint: NSEvent.mouseLocation) ?? false

        panel.ignoresMouseEvents = !isInside
    }
}

// MARK: - Animation

extension GroupPanelController {
    /// 缩放到 0 的矩阵不可逆，Core Animation 无法插值，收起的终点用一个看不见的比例代替
    private static let collapsedScale: CGFloat = 0.001

    /// 展开：整个面板以 tile 图标中心为锚点从 0.1 倍放大到原尺寸，同时淡入
    private func animateExpansion() {
        guard let layer = containerView.layer else { return }

        let initialTransform = Self.scaleTransform(
            GroupPanelMetrics.expandInitialScale,
            around: windowPoint(fromScreen: scaleAnchor),
            of: layer
        )

        let transform = Self.animation(
            keyPath: "transform",
            from: NSValue(caTransform3D: initialTransform),
            to: NSValue(caTransform3D: CATransform3DIdentity),
            duration: GroupPanelMetrics.expandDuration,
            timing: Self.timingFunction(GroupPanelMetrics.expandTimingControlPoints)
        )

        let opacity = Self.animation(
            keyPath: "opacity",
            from: 0,
            to: 1,
            duration: GroupPanelMetrics.expandFadeDuration,
            timing: CAMediaTimingFunction(name: .easeOut)
        )

        layer.add(transform, forKey: "transform")
        layer.add(opacity, forKey: "opacity")
    }

    /// 收起：从当前画面开始，整个面板向 tile 图标中心缩小并淡出，淡出先于缩放结束
    private func animateCollapse(of layer: CALayer) {
        // 先记下当前画面，再移除进行中的动画，打断展开时从这一帧开始收起
        let currentTransform = layer.presentation()?.transform ?? CATransform3DIdentity
        let currentOpacity = layer.presentation()?.opacity ?? 1
        layer.removeAllAnimations()

        let collapsedTransform = Self.scaleTransform(
            Self.collapsedScale,
            around: windowPoint(fromScreen: scaleAnchor),
            of: layer
        )

        let transform = Self.animation(
            keyPath: "transform",
            from: NSValue(caTransform3D: currentTransform),
            to: NSValue(caTransform3D: collapsedTransform),
            duration: GroupPanelMetrics.collapseDuration,
            timing: Self.timingFunction(GroupPanelMetrics.collapseTimingControlPoints)
        )

        let opacity = Self.animation(
            keyPath: "opacity",
            from: currentOpacity,
            to: 0,
            duration: GroupPanelMetrics.collapseFadeDuration,
            timing: CAMediaTimingFunction(name: .easeIn)
        )

        // 结束后保持收起的画面直到窗口隐藏；图层的模型值始终是展开状态
        for animation in [transform, opacity] {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animation.keyPath)
        }
    }

    /// 进入下一层时新层级的出现：
    /// 以被点击的图标中心为锚点，按展开同样的缩放与淡入曲线出现
    /// - Parameters:
    ///   - level: 新层级
    ///   - iconCenter: 被点击的图标中心，AppKit 屏幕坐标
    private func animateEntrance(of level: GroupPanelLevel, from iconCenter: CGPoint) {
        guard let layer = level.view.layer else { return }

        let initialTransform = Self.scaleTransform(
            GroupPanelMetrics.expandInitialScale,
            around: level.localPoint(fromScreen: iconCenter),
            of: layer
        )

        let transform = Self.animation(
            keyPath: "transform",
            from: NSValue(caTransform3D: initialTransform),
            to: NSValue(caTransform3D: CATransform3DIdentity),
            duration: GroupPanelMetrics.expandDuration,
            timing: Self.timingFunction(GroupPanelMetrics.expandTimingControlPoints)
        )

        let opacity = Self.animation(
            keyPath: "opacity",
            from: 0,
            to: 1,
            duration: GroupPanelMetrics.expandFadeDuration,
            timing: CAMediaTimingFunction(name: .easeOut)
        )

        layer.add(transform, forKey: "transform")
        layer.add(opacity, forKey: "opacity")
    }

    /// 返回上一层时当前层级的离开：
    /// 按收起同样的方式缩向父层级中它的图标中心并淡出，结束后移除
    /// - Parameters:
    ///   - level: 离开的层级
    ///   - iconCenter: 父层级中它的图标中心，AppKit 屏幕坐标；找不到时只淡出
    private func animateReturn(of level: GroupPanelLevel, to iconCenter: CGPoint?) {
        guard let layer = level.view.layer else { return }

        var animations = [
            Self.animation(
                keyPath: "opacity",
                from: 1,
                to: 0,
                duration: GroupPanelMetrics.collapseFadeDuration,
                timing: CAMediaTimingFunction(name: .easeIn)
            ),
        ]

        if let iconCenter {
            let collapsedTransform = Self.scaleTransform(
                Self.collapsedScale,
                around: level.localPoint(fromScreen: iconCenter),
                of: layer
            )

            animations.append(Self.animation(
                keyPath: "transform",
                from: NSValue(caTransform3D: CATransform3DIdentity),
                to: NSValue(caTransform3D: collapsedTransform),
                duration: GroupPanelMetrics.collapseDuration,
                timing: Self.timingFunction(GroupPanelMetrics.collapseTimingControlPoints)
            ))
        }

        // 结束后保持看不见的画面，直到层级被移除
        for animation in animations {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animation.keyPath)
        }

        removeDepartingLevel(level, after: GroupPanelMetrics.collapseDuration)
    }

    /// 进入下一层时旧层级原地淡出、不缩放，等新层级展开结束再移除
    ///
    /// 新层级从旧层级里被点击的图标长出来，
    /// 展开途中的画面落在图标与新层级之间，可能越出新层级的范围；
    /// 旧层级留到展开结束，窗口保持两者的并集，这部分画面才不被窗口边界裁掉
    private func fadeOut(_ level: GroupPanelLevel) {
        guard let layer = level.view.layer else { return }

        let animation = Self.animation(
            keyPath: "opacity",
            from: 1,
            to: 0,
            duration: GroupPanelMetrics.enterFadeOutDuration,
            timing: CAMediaTimingFunction(name: .linear)
        )

        // 淡出后保持透明，直到新层级展开结束、层级被移除
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "opacity")

        removeDepartingLevel(level, after: GroupPanelMetrics.expandDuration)
    }

    /// 返回上一层时父层级原地淡入、不缩放
    private func fadeIn(_ level: GroupPanelLevel) {
        level.view.layer?.add(
            Self.animation(
                keyPath: "opacity",
                from: 0,
                to: 1,
                duration: GroupPanelMetrics.backFadeInDuration,
                timing: CAMediaTimingFunction(name: .linear)
            ),
            forKey: "opacity"
        )
    }

    /// 动画时长过后在主线程收尾
    ///
    /// 按时长而不是 Core Animation 的完成回调收尾：屏幕锁定、显示器休眠时回调可能一直不来，面板会停在透明却仍挡住点击的状态
    private func afterAnimation(
        _ duration: CFTimeInterval,
        _ completion: @escaping @MainActor () -> Void
    ) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            completion()
        }
    }

    /// 屏幕坐标换算到窗口坐标，即 contentView 图层的坐标系
    private func windowPoint(fromScreen point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)
    }
}

// MARK: - Helpers

extension GroupPanelController {
    /// 以图层坐标系中的 point 为中心缩放的变换
    ///
    /// 图层变换以 anchorPoint 为原点：先把 point 平移到 anchorPoint，缩放后再移回去
    private static func scaleTransform(
        _ scale: CGFloat,
        around point: CGPoint,
        of layer: CALayer
    ) -> CATransform3D {
        let offsetX = point.x - (layer.bounds.minX + layer.bounds.width * layer.anchorPoint.x)
        let offsetY = point.y - (layer.bounds.minY + layer.bounds.height * layer.anchorPoint.y)

        let translation = CATransform3DMakeTranslation(offsetX, offsetY, 0)
        let transform = CATransform3DScale(translation, scale, scale, 1)

        return CATransform3DTranslate(transform, -offsetX, -offsetY, 0)
    }

    /// 由四个控制点构造三次贝塞尔时间曲线
    private static func timingFunction(_ controlPoints: [Float]) -> CAMediaTimingFunction {
        CAMediaTimingFunction(
            controlPoints: controlPoints[0],
            controlPoints[1],
            controlPoints[2],
            controlPoints[3]
        )
    }

    /// 构造一段 `CABasicAnimation`；
    /// 结束后是否保持画面（`fillMode` 等）由调用方设置
    private static func animation(
        keyPath: String,
        from fromValue: Any,
        to toValue: Any,
        duration: CFTimeInterval,
        timing: CAMediaTimingFunction
    ) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = timing

        return animation
    }
}
