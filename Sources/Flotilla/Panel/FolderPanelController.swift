import AppKit
import os
import QuartzCore

// MARK: - FolderPanelController

/// 管理全局唯一的面板：按 tile 摆放、构建每个层级、嵌套导航（需求 1），以及展开、收起与转场动画
///
/// 每个层级是一个 `FolderPanelLevel`，四周带着阴影留白；窗口 frame 是当前全部层级的并集。
/// 展开与收起只对 contentView 图层的 transform 与 opacity 做动画，锚点在 tile 图标中心
@MainActor
final class FolderPanelController {
    /// 面板相关的日志
    private nonisolated static let logger = Logger(subsystem: "com.rakuyo.flotilla", category: "FolderPanelController")

    /// 面板窗口
    let panel = FolderPanel()

    /// 请求收起面板：按下 Esc、点击 App 项之后调用，由 `DockFolderPresenter` 更新状态并收起
    var dismissRequestHandler: (() -> Void)? = nil

    /// 面板的 contentView，承载全部层级；展开与收起的动画作用在它的图层上
    private let containerView = NSView()

    /// 文件夹树的唯一数据源
    private let store: FolderStore

    /// 用户设置，决定子文件夹图标里的预览数量
    private let preferences: Preferences

    /// 本次展开的定位依据
    private var anchor: DockTileAnchor? = nil

    /// 展开、收起时整个面板缩放的锚点（tile 图标中心），AppKit 屏幕坐标
    private var scaleAnchor = CGPoint.zero

    /// 从根文件夹到当前层级的文件夹 id
    private var path: [UUID] = []

    /// 当前层级
    private var currentLevel: FolderPanelLevel? = nil

    /// 转场中正在淡出、缩走的层级，动画结束后移除
    private var departingLevels: [FolderPanelLevel] = []

    /// 本次展开中各文件夹网格的滚动位置，返回上一层时恢复
    private var scrollOffsets: [UUID: CGPoint] = [:]

    /// 动画代数：每次立即隐藏、开始收起都加一，过期的收起收尾据此放弃
    private var animationGeneration = 0

    /// 展开期间跟踪鼠标移动的监听，决定点击是否穿透面板
    private var mouseMonitors: [Any] = []

    /// 创建面板控制器
    /// - Parameters:
    ///   - store: 文件夹树的唯一数据源
    ///   - preferences: 用户设置，决定子文件夹图标里的预览数量
    init(store: FolderStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences

        containerView.wantsLayer = true
        panel.contentView = containerView

        panel.cancelHandler = { [weak self] in
            self?.dismissRequestHandler?()
        }
    }

    /// 沿导航路径在文件夹树里逐层查找，返回当前层级的文件夹
    /// - Returns: 根文件夹已不是根文件夹，或路径上任何一层已不在上一层之内时为 nil
    static func folder(at path: [UUID], in rootFolders: [Folder]) -> Folder? {
        guard
            let rootID = path.first,
            var folder = rootFolders.first(where: { $0.id == rootID })
        else {
            return nil
        }

        for folderID in path.dropFirst() {
            let subfolder = folder.items.lazy
                .compactMap { item -> Folder? in
                    guard case .folder(let subfolder) = item, subfolder.id == folderID else { return nil }
                    return subfolder
                }
                .first
            guard let subfolder else { return nil }

            folder = subfolder
        }
        return folder
    }
}

// MARK: - Presenting

extension FolderPanelController {
    /// 展开根文件夹的根层级；已有面板时旧面板立即消失，新面板按展开动画出现
    func expand(rootFolder: Folder, anchor: DockTileAnchor) {
        hideImmediately()

        self.anchor = anchor
        path = [rootFolder.id]

        let (level, placement) = makeLevel(for: rootFolder, anchor: anchor)
        scaleAnchor = placement.anchor
        install(level)

        // 先装好动画再显示，第一帧就是收起的画面；只用 orderFrontRegardless，不激活 Flotilla（需求 6）
        animateExpansion()
        panel.orderFrontRegardless()
        panel.makeKey()

        startTrackingMouse()
        updateMousePassthrough()
    }

    /// 按收起动画收起面板；打断进行中的展开时从当前画面开始收起
    func collapse() {
        guard panel.isVisible, let layer = containerView.layer else { return }

        animationGeneration += 1
        let generation = animationGeneration

        // 收起一开始就让点击全部穿透，面板不再挡住下面的窗口
        stopTrackingMouse()
        panel.ignoresMouseEvents = true

        animateCollapse(of: layer)

        // 收起期间又有新的展开或收起时，这次的收尾作废
        afterAnimation(FolderPanelMetrics.collapseDuration) { [weak self] in
            guard let self, generation == animationGeneration else { return }

            hideImmediately()
        }
    }

    /// 文件夹树变化后按新数据重建当前层级，保留滚动位置，不带动画
    /// - Returns: 当前文件夹已不在该根文件夹之下时为 false，由调用方收起面板
    func reload() -> Bool {
        guard let anchor, let folder = Self.folder(at: path, in: store.rootFolders) else { return false }

        if let currentLevel {
            saveScrollOffset(of: currentLevel)
        }

        // 转场中的层级一并丢弃，只留下按新数据重建的当前层级
        removeAllLevels()
        install(makeLevel(for: folder, anchor: anchor).level)
        updateMousePassthrough()

        return true
    }
}

// MARK: - Navigation

extension FolderPanelController {
    /// 点击网格中的一项：App 直接启动并收起面板（需求 9），子文件夹在同一个面板里进入
    private func select(_ item: FolderItem) {
        switch item {
        case .app(let app):
            launch(app)

        case .folder(let folder):
            enter(folder)
        }
    }

    /// 进入子文件夹：新层级从被点击的子文件夹图标里长出来，旧层级原地淡出
    private func enter(_ folder: Folder) {
        guard
            let anchor,
            let parent = currentLevel,
            let iconCenter = parent.iconCenterOnScreen(of: folder.id)
        else {
            return
        }

        saveScrollOffset(of: parent)
        path.append(folder.id)

        // 新层级叠在旧层级之上，旧层级转入淡出队列
        let level = makeLevel(for: folder, anchor: anchor).level
        departingLevels.append(parent)
        install(level)
        updateMousePassthrough()

        animateEntrance(of: level, from: iconCenter)
        fadeOut(parent)
    }

    /// 返回上一层：当前层级缩回父层级里该子文件夹的图标并淡出，父层级原地淡入；上一层已不存在时收起面板
    private func goBack() {
        guard let anchor, let child = currentLevel, path.count > 1 else { return }

        path.removeLast()

        guard let parentFolder = Self.folder(at: path, in: store.rootFolders) else {
            dismissRequestHandler?()
            return
        }

        // 父层级按记下的滚动位置重建，放在子层级下面
        let parent = makeLevel(for: parentFolder, anchor: anchor).level
        departingLevels.append(child)
        install(parent, below: child.view)
        updateMousePassthrough()

        animateReturn(of: child, to: parent.iconCenterOnScreen(of: child.folderID))
        fadeIn(parent)
    }

    /// 启动 App，随即请求收起面板
    private func launch(_ app: AppReference) {
        let name = app.displayName

        NSWorkspace.shared.openApplication(at: app.url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }

            Self.logger.error("启动 \(name, privacy: .public) 失败：\(error.localizedDescription, privacy: .public)")
        }

        dismissRequestHandler?()
    }
}

// MARK: - Levels

extension FolderPanelController {
    /// 构建一个层级：背景、标题区与网格，并按 tile 算出它在屏幕上的位置
    /// - Returns: 层级，以及算出它位置的 `FolderPanelPlacement`
    private func makeLevel(
        for folder: Folder,
        anchor: DockTileAnchor
    ) -> (level: FolderPanelLevel, placement: FolderPanelPlacement) {
        let visibleFrame = anchor.screen.visibleFrame

        // 网格的列数与显示行数受 tile 旁可用的空间限制
        let layout = FolderGridLayout(
            itemCount: folder.items.count,
            availableSize: FolderPanelPlacement.availableBodySize(
                tileFrame: anchor.tileFrame,
                edge: anchor.edge,
                visibleFrame: visibleFrame
            )
        )
        let placement = FolderPanelPlacement(
            bodySize: layout.bodySize,
            tileFrame: anchor.tileFrame,
            edge: anchor.edge,
            visibleFrame: visibleFrame
        )

        // 视图是轮廓（主体加尾巴尖端）的外接矩形四周再扩出阴影留白，同时盖住 tile 图标中心的缩放锚点
        let margin = FolderPanelMetrics.shadowMargin
        let screenFrame = placement.bodyFrame
            .union(CGRect(origin: placement.tailTip, size: .zero))
            .insetBy(dx: -margin, dy: -margin)
        let origin = screenFrame.origin

        let view = FolderPanelBackgroundView(
            frame: CGRect(origin: .zero, size: screenFrame.size),
            bodyRect: placement.bodyFrame.offsetBy(dx: -origin.x, dy: -origin.y),
            tailTip: CGPoint(x: placement.tailTip.x - origin.x, y: placement.tailTip.y - origin.y),
            edge: anchor.edge
        )
        view.bodyView.addSubview(makeHeader(for: folder, bodySize: layout.bodySize))

        // 空文件夹只有标题区，格内为空
        let scrollView = folder.items.isEmpty ? nil : makeScrollView(for: folder, layout: layout)
        if let scrollView {
            view.bodyView.addSubview(scrollView)
        }

        let level = FolderPanelLevel(
            folderID: folder.id,
            view: view,
            screenFrame: screenFrame,
            scrollView: scrollView,
            gridView: scrollView?.documentView as? FolderGridView
        )
        return (level, placement)
    }

    /// 标题区：占面板主体顶部，子层级带返回按钮
    private func makeHeader(for folder: Folder, bodySize: CGSize) -> FolderNavigationHeaderView {
        let backHandler: (() -> Void)? = path.count > 1
            ? { [weak self] in self?.goBack() }
            : nil

        let header = FolderNavigationHeaderView(title: folder.name, backHandler: backHandler)
        let height = FolderPanelMetrics.headerHeight
        header.frame = CGRect(x: 0, y: bodySize.height - height, width: bodySize.width, height: height)

        return header
    }

    /// 网格所在的滚动视图：向右伸进主体右侧的留白，overlay 滚动条落在留白里；恢复这个文件夹上次的滚动位置
    private func makeScrollView(for folder: Folder, layout: FolderGridLayout) -> NSScrollView {
        let cell = FolderPanelMetrics.cellSize
        let sideInset = FolderPanelMetrics.gridSideInset

        let scrollView = NSScrollView(frame: CGRect(
            x: sideInset,
            y: FolderPanelMetrics.gridBottomInset,
            width: layout.gridSize.width + sideInset - FolderPanelMetrics.scrollerTrailingInset,
            height: CGFloat(layout.visibleRowCount) * cell
        ))

        // 只在行数超出显示行数时垂直滚动；放得下时关掉回弹
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.hasVerticalScroller = layout.needsScrolling
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = layout.needsScrolling ? .automatic : .none
        scrollView.horizontalScrollElasticity = .none

        scrollView.documentView = FolderGridView(
            items: folder.items,
            layout: layout,
            previewIconCount: preferences.previewIconCount
        ) { [weak self] in
            self?.select($0)
        }

        if let offset = scrollOffsets[folder.id] {
            scrollView.contentView.scroll(to: offset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        return scrollView
    }

    /// 把层级设为当前层级并放进面板
    /// - Parameters:
    ///   - level: 新的当前层级
    ///   - sibling: 不为 nil 时放在它下面，否则放在最上面
    private func install(_ level: FolderPanelLevel, below sibling: NSView? = nil) {
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

        guard let frame = levels.map(\.screenFrame).reduce(nil, { $0?.union($1) ?? $1 }) else { return }

        panel.setFrame(frame, display: false)

        for level in levels {
            level.view.frame = level.screenFrame.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
    }

    /// 转场结束后移除离开的层级，窗口收缩到剩下的层级
    private func removeDepartingLevel(_ level: FolderPanelLevel, after delay: CFTimeInterval) {
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

    /// 移除全部层级
    private func removeAllLevels() {
        for level in departingLevels + [currentLevel].compactMap(\.self) {
            level.view.removeFromSuperview()
        }

        departingLevels = []
        currentLevel = nil
    }

    /// 记下层级网格当前的滚动位置
    private func saveScrollOffset(of level: FolderPanelLevel) {
        guard let scrollView = level.scrollView else { return }

        scrollOffsets[level.folderID] = scrollView.contentView.bounds.origin
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
    }
}

// MARK: - Mouse Passthrough

extension FolderPanelController {
    /// 开始跟踪鼠标移动：窗口比轮廓大得多（阴影留白、盖住 tile 的锚点延伸），轮廓以外的点击要穿透到下面
    ///
    /// 只在鼠标移动时更新，拖动期间保持不变，按下的格子才收得到抬起
    private func startTrackingMouse() {
        guard mouseMonitors.isEmpty else { return }

        // 鼠标不在面板上时移动事件发往其它 App，在面板上时发往面板自己
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.updateMousePassthrough()
        }
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updateMousePassthrough()
            return event
        }

        mouseMonitors = [globalMonitor, localMonitor].compactMap(\.self)
    }

    /// 停止跟踪鼠标移动
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

extension FolderPanelController {
    /// 缩放到 0 的矩阵不可逆，Core Animation 无法插值，收起的终点用一个看不见的比例代替
    private static let collapsedScale: CGFloat = 0.001

    /// 展开：整个面板以 tile 图标中心为锚点从 0.1 倍放大到原尺寸，同时淡入
    private func animateExpansion() {
        guard let layer = containerView.layer else { return }

        let initialTransform = Self.scaleTransform(
            FolderPanelMetrics.expandInitialScale,
            around: windowPoint(fromScreen: scaleAnchor),
            of: layer
        )

        let transform = Self.animation(
            keyPath: "transform",
            from: NSValue(caTransform3D: initialTransform),
            to: NSValue(caTransform3D: CATransform3DIdentity),
            duration: FolderPanelMetrics.expandDuration,
            timing: Self.timingFunction(FolderPanelMetrics.expandTimingControlPoints)
        )
        let opacity = Self.animation(
            keyPath: "opacity",
            from: 0,
            to: 1,
            duration: FolderPanelMetrics.expandFadeDuration,
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
            duration: FolderPanelMetrics.collapseDuration,
            timing: Self.timingFunction(FolderPanelMetrics.collapseTimingControlPoints)
        )
        let opacity = Self.animation(
            keyPath: "opacity",
            from: currentOpacity,
            to: 0,
            duration: FolderPanelMetrics.collapseFadeDuration,
            timing: CAMediaTimingFunction(name: .easeIn)
        )

        // 结束后保持收起的画面直到窗口隐藏；图层的模型值始终是展开状态
        for animation in [transform, opacity] {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animation.keyPath)
        }
    }

    /// 进入子文件夹时新层级的出现：以被点击的子文件夹图标中心为锚点，按展开同样的缩放与淡入曲线出现
    /// - Parameters:
    ///   - level: 新层级
    ///   - iconCenter: 被点击的子文件夹图标中心，AppKit 屏幕坐标
    private func animateEntrance(of level: FolderPanelLevel, from iconCenter: CGPoint) {
        guard let layer = level.view.layer else { return }

        let initialTransform = Self.scaleTransform(
            FolderPanelMetrics.expandInitialScale,
            around: level.localPoint(fromScreen: iconCenter),
            of: layer
        )

        let transform = Self.animation(
            keyPath: "transform",
            from: NSValue(caTransform3D: initialTransform),
            to: NSValue(caTransform3D: CATransform3DIdentity),
            duration: FolderPanelMetrics.expandDuration,
            timing: Self.timingFunction(FolderPanelMetrics.expandTimingControlPoints)
        )
        let opacity = Self.animation(
            keyPath: "opacity",
            from: 0,
            to: 1,
            duration: FolderPanelMetrics.expandFadeDuration,
            timing: CAMediaTimingFunction(name: .easeOut)
        )

        layer.add(transform, forKey: "transform")
        layer.add(opacity, forKey: "opacity")
    }

    /// 返回上一层时当前层级的离开：按收起同样的方式缩向父层级中该子文件夹的图标中心并淡出，结束后移除
    /// - Parameters:
    ///   - level: 离开的层级
    ///   - iconCenter: 父层级中该子文件夹的图标中心，AppKit 屏幕坐标；找不到时只淡出
    private func animateReturn(of level: FolderPanelLevel, to iconCenter: CGPoint?) {
        guard let layer = level.view.layer else { return }

        var animations = [
            Self.animation(
                keyPath: "opacity",
                from: 1,
                to: 0,
                duration: FolderPanelMetrics.collapseFadeDuration,
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
                duration: FolderPanelMetrics.collapseDuration,
                timing: Self.timingFunction(FolderPanelMetrics.collapseTimingControlPoints)
            ))
        }

        // 结束后保持看不见的画面，直到层级被移除
        for animation in animations {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animation.keyPath)
        }

        removeDepartingLevel(level, after: FolderPanelMetrics.collapseDuration)
    }

    /// 进入子文件夹时旧层级原地淡出、不缩放，结束后移除
    private func fadeOut(_ level: FolderPanelLevel) {
        guard let layer = level.view.layer else { return }

        let animation = Self.animation(
            keyPath: "opacity",
            from: 1,
            to: 0,
            duration: FolderPanelMetrics.enterFadeOutDuration,
            timing: CAMediaTimingFunction(name: .linear)
        )

        // 结束后保持透明，直到层级被移除
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "opacity")

        removeDepartingLevel(level, after: FolderPanelMetrics.enterFadeOutDuration)
    }

    /// 返回上一层时父层级原地淡入、不缩放
    private func fadeIn(_ level: FolderPanelLevel) {
        level.view.layer?.add(
            Self.animation(
                keyPath: "opacity",
                from: 0,
                to: 1,
                duration: FolderPanelMetrics.backFadeInDuration,
                timing: CAMediaTimingFunction(name: .linear)
            ),
            forKey: "opacity"
        )
    }

    /// 动画时长过后在主线程收尾
    ///
    /// 按时长而不是 Core Animation 的完成回调收尾：屏幕锁定、显示器休眠时回调可能一直不来，面板会停在透明却仍挡住点击的状态
    private func afterAnimation(_ duration: CFTimeInterval, _ completion: @escaping @MainActor () -> Void) {
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

extension FolderPanelController {
    /// 以图层坐标系中的 point 为中心缩放的变换
    ///
    /// 图层变换以 anchorPoint 为原点：先把 point 平移到 anchorPoint，缩放后再移回去
    private static func scaleTransform(_ scale: CGFloat, around point: CGPoint, of layer: CALayer) -> CATransform3D {
        let offsetX = point.x - (layer.bounds.minX + layer.bounds.width * layer.anchorPoint.x)
        let offsetY = point.y - (layer.bounds.minY + layer.bounds.height * layer.anchorPoint.y)

        let transform = CATransform3DScale(CATransform3DMakeTranslation(offsetX, offsetY, 0), scale, scale, 1)
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

    /// 构造一段基础动画
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
