import AppKit
import os
import QuartzCore

// MARK: - FolderPanelController

/// 管理全局唯一的面板：按锚点摆放、构建每一层内容、嵌套导航（需求 1），以及展开、收起与转场动画
///
/// 窗口 frame 直接设为最终尺寸，展开与收起只对 contentView 图层的 transform 与 opacity 做动画，锚点在尾巴尖端
@MainActor
final class FolderPanelController {
    #warning("TODO: 待实测 展开 0.2 秒 ease-out 自 0.2 倍、收起 0.15 秒、转场 0.2 秒自 0.9 倍；根层级不显示导航头；Esc 直接收起")

    /// 面板相关的日志
    private nonisolated static let logger = Logger(subsystem: "com.rakuyo.flotilla", category: "FolderPanelController")

    /// 面板窗口
    let panel = FolderPanel()

    /// 请求收起面板：按下 Esc、点击 App 项之后调用，由 `DockFolderPresenter` 更新状态并收起
    var dismissRequestHandler: (() -> Void)? = nil

    /// 面板的背景，同时是面板的 contentView
    private let backgroundView = FolderPanelBackgroundView()

    /// 文件夹树的唯一数据源
    private let store: FolderStore

    /// 用户设置，决定子文件夹图标里的预览数量
    private let preferences: Preferences

    /// 本次展开的定位依据
    private var anchor: DockTileAnchor? = nil

    /// 从根文件夹到当前层级的文件夹 id
    private var path: [UUID] = []

    /// 当前层级的内容
    private var currentPage: NSView? = nil

    /// 动画代数：每次立即隐藏、开始收起都加一，过期动画的完成回调据此放弃
    private var animationGeneration = 0

    /// 当前层级是否为子文件夹：只有子文件夹显示导航头
    private var isShowingSubfolder: Bool {
        path.count > 1
    }

    /// 创建面板控制器
    /// - Parameters:
    ///   - store: 文件夹树的唯一数据源
    ///   - preferences: 用户设置，决定子文件夹图标里的预览数量
    init(store: FolderStore, preferences: Preferences) {
        self.store = store
        self.preferences = preferences

        panel.contentView = backgroundView
        panel.cancelHandler = { [weak self] in
            self?.dismissRequestHandler?()
        }
    }

    /// 沿导航路径在文件夹树里逐层查找，返回当前层级的文件夹
    /// - Returns: 根文件夹已不是根文件夹，或路径上任何一层已不在上一层之内时为 nil
    static func folder(at path: [UUID], in rootFolders: [Folder]) -> Folder? {
        guard let rootID = path.first, var folder = rootFolders.first(where: { $0.id == rootID }) else { return nil }

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
        backgroundView.edge = anchor.edge
        showPage(for: rootFolder)

        // 动画期间窗口阴影不会随图层缩放，先关掉，展开结束后按最终形状重新生成
        panel.hasShadow = false
        panel.orderFrontRegardless()
        panel.makeKey()

        animateExpansion()
    }

    /// 按收起动画收起面板；打断进行中的展开时从当前画面开始收起
    func collapse() {
        guard panel.isVisible, let layer = backgroundView.layer else { return }

        animationGeneration += 1
        let generation = animationGeneration

        // 先记下当前画面，再移除进行中的动画，收起从这一帧开始
        let currentTransform = layer.presentation()?.transform ?? CATransform3DIdentity
        let currentOpacity = layer.presentation()?.opacity ?? 1
        layer.removeAllAnimations()
        panel.hasShadow = false

        let animations = [
            Self.animation(
                keyPath: "transform",
                from: NSValue(caTransform3D: currentTransform),
                to: NSValue(caTransform3D: collapsedTransform(of: layer)),
                duration: FolderPanelMetrics.collapseDuration,
                timing: .easeIn
            ),
            Self.animation(
                keyPath: "opacity",
                from: currentOpacity,
                to: 0,
                duration: FolderPanelMetrics.collapseDuration,
                timing: .easeIn
            ),
        ]

        // 动画结束后保持收起的画面，直到窗口隐藏，图层的模型值始终是展开状态
        for animation in animations {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: animation.keyPath)
        }

        // 收起期间又有新的展开或收起时，这次的收尾作废
        afterAnimation(FolderPanelMetrics.collapseDuration) { [weak self] in
            guard let self, generation == animationGeneration else { return }

            hideImmediately()
        }
    }

    /// 文件夹树变化后按新数据重建当前层级
    /// - Returns: 当前文件夹已不在该根文件夹之下时为 false，由调用方收起面板
    func reload() -> Bool {
        guard let folder = Self.folder(at: path, in: store.rootFolders) else { return false }

        showPage(for: folder)
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
            path.append(folder.id)
            navigate(to: folder, fromScale: FolderPanelMetrics.navigationScale)
        }
    }

    /// 返回上一层；上一层已不存在时收起面板
    private func goBack() {
        guard isShowingSubfolder else { return }

        path.removeLast()

        guard let folder = Self.folder(at: path, in: store.rootFolders) else {
            dismissRequestHandler?()
            return
        }

        navigate(to: folder, fromScale: 1 / FolderPanelMetrics.navigationScale)
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

// MARK: - Private

extension FolderPanelController {
    /// 不带动画地显示一层内容：替换全部内容，窗口直接设为该层的位置与尺寸
    private func showPage(for folder: Folder) {
        guard let anchor else { return }

        let (layout, placement) = geometry(for: folder, anchor: anchor)
        let page = makePage(for: folder, layout: layout)

        panel.setFrame(placement.frame, display: false)
        backgroundView.tailTip = placement.tailTip

        for subview in backgroundView.contentContainer.subviews {
            subview.removeFromSuperview()
        }

        page.frame = Self.centeredFrame(size: layout.panelSize, in: backgroundView.bodyRect)
        backgroundView.contentContainer.addSubview(page)
        currentPage = page
    }

    /// 带转场地切换到另一层：旧内容淡出，新内容淡入并缩放到原尺寸，面板尺寸同时做动画，尾巴尖端保持不动
    private func navigate(to folder: Folder, fromScale initialScale: CGFloat) {
        guard let anchor else { return }

        let (layout, placement) = geometry(for: folder, anchor: anchor)
        let oldPage = currentPage
        let newPage = makePage(for: folder, layout: layout)

        // 新内容先放在当前主体区域的中央；四边留白可伸缩，窗口尺寸变化期间它保持自身尺寸并一直居中
        newPage.frame = Self.centeredFrame(size: layout.panelSize, in: backgroundView.bodyRect)
        backgroundView.contentContainer.addSubview(newPage)
        currentPage = newPage
        backgroundView.tailTip = placement.tailTip

        NSAnimationContext.runAnimationGroup { context in
            context.duration = FolderPanelMetrics.navigationDuration
            panel.animator().setFrame(placement.frame, display: true)
        }

        fadeOut(oldPage)
        animateAppearance(of: newPage, fromScale: initialScale)

        // 面板尺寸变了，阴影按新的形状重新生成
        afterAnimation(FolderPanelMetrics.navigationDuration) { [weak self] in
            self?.panel.invalidateShadow()
        }
    }

    /// 按当前层级算出网格布局与面板位置
    private func geometry(
        for folder: Folder,
        anchor: DockTileAnchor
    ) -> (layout: FolderGridLayout, placement: FolderPanelPlacement) {
        let visibleFrame = anchor.screen.visibleFrame

        let layout = FolderGridLayout(
            itemCount: folder.items.count,
            availableSize: FolderPanelPlacement.availableBodySize(
                tileFrame: anchor.tileFrame,
                edge: anchor.edge,
                visibleFrame: visibleFrame
            ),
            hasHeader: isShowingSubfolder
        )
        let placement = FolderPanelPlacement(
            bodySize: layout.panelSize,
            tileFrame: anchor.tileFrame,
            edge: anchor.edge,
            visibleFrame: visibleFrame
        )

        return (layout, placement)
    }

    /// 构建一层内容：可滚动的网格，子文件夹层级再加上导航头；尺寸即面板主体尺寸
    private func makePage(for folder: Folder, layout: FolderGridLayout) -> NSView {
        let inset = FolderPanelMetrics.contentInset
        let size = layout.panelSize
        let headerHeight = isShowingSubfolder ? FolderPanelMetrics.headerHeight : 0

        let page = NSView(frame: CGRect(origin: .zero, size: size))
        page.wantsLayer = true
        page.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]

        // 网格高度超出屏幕时靠滚动查看，滚动条用 overlay 样式；放得下时关掉回弹
        let scrollView = NSScrollView(frame: CGRect(
            x: inset,
            y: inset,
            width: size.width - 2 * inset,
            height: size.height - 2 * inset - headerHeight
        ))
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
        page.addSubview(scrollView)

        guard isShowingSubfolder else { return page }

        let header = FolderNavigationHeaderView(title: folder.name) { [weak self] in
            self?.goBack()
        }
        header.frame = CGRect(
            x: inset,
            y: size.height - inset - headerHeight,
            width: size.width - 2 * inset,
            height: headerHeight
        )
        page.addSubview(header)

        return page
    }

    /// 立即隐藏面板，丢弃进行中的动画与全部内容
    private func hideImmediately() {
        animationGeneration += 1

        backgroundView.layer?.removeAllAnimations()
        panel.orderOut(nil)

        for subview in backgroundView.contentContainer.subviews {
            subview.removeFromSuperview()
        }

        currentPage = nil
        path = []
        anchor = nil
    }
}

// MARK: - Animation

extension FolderPanelController {
    /// 展开动画：以尾巴尖端为锚点，从收起的比例放大到原尺寸并淡入；结束后恢复窗口阴影
    private func animateExpansion() {
        guard let layer = backgroundView.layer else { return }

        let generation = animationGeneration
        let duration = FolderPanelMetrics.expandDuration

        layer.add(
            Self.animation(
                keyPath: "transform",
                from: NSValue(caTransform3D: collapsedTransform(of: layer)),
                to: NSValue(caTransform3D: CATransform3DIdentity),
                duration: duration,
                timing: .easeOut
            ),
            forKey: "transform"
        )
        layer.add(
            Self.animation(keyPath: "opacity", from: 0, to: 1, duration: duration, timing: .easeOut),
            forKey: "opacity"
        )

        // 展开期间被收起或切换时，阴影由新的动画负责
        afterAnimation(duration) { [weak self] in
            guard let self, generation == animationGeneration else { return }

            panel.hasShadow = true
            panel.invalidateShadow()
        }
    }

    /// 转场中新内容的出现：以自身中心为锚点从 scale 缩放到原尺寸并淡入
    private func animateAppearance(of page: NSView, fromScale scale: CGFloat) {
        guard let layer = page.layer else { return }

        let center = CGPoint(x: page.bounds.midX, y: page.bounds.midY)
        let duration = FolderPanelMetrics.navigationDuration

        layer.add(
            Self.animation(
                keyPath: "transform",
                from: NSValue(caTransform3D: Self.scaleTransform(scale, around: center, of: layer)),
                to: NSValue(caTransform3D: CATransform3DIdentity),
                duration: duration,
                timing: .easeOut
            ),
            forKey: "transform"
        )
        layer.add(
            Self.animation(keyPath: "opacity", from: 0, to: 1, duration: duration, timing: .easeOut),
            forKey: "opacity"
        )
    }

    /// 转场中旧内容的淡出，结束后移除
    private func fadeOut(_ page: NSView?) {
        guard let page, let layer = page.layer else { return }

        let animation = Self.animation(
            keyPath: "opacity",
            from: 1,
            to: 0,
            duration: FolderPanelMetrics.navigationDuration,
            timing: .easeOut
        )
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "opacity")

        afterAnimation(FolderPanelMetrics.navigationDuration) { [weak page] in
            page?.removeFromSuperview()
        }
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

    /// 收起状态的变换：以尾巴尖端为锚点缩小到 `collapsedScale`
    private func collapsedTransform(of layer: CALayer) -> CATransform3D {
        let origin = panel.frame.origin
        let tailTip = CGPoint(
            x: backgroundView.tailTip.x - origin.x,
            y: backgroundView.tailTip.y - origin.y
        )

        return Self.scaleTransform(FolderPanelMetrics.collapsedScale, around: tailTip, of: layer)
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

    /// 构造一段基础动画
    private static func animation(
        keyPath: String,
        from fromValue: Any,
        to toValue: Any,
        duration: CFTimeInterval,
        timing: CAMediaTimingFunctionName
    ) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = fromValue
        animation.toValue = toValue
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        return animation
    }

    /// size 居中放进 rect 后的 frame
    private static func centeredFrame(size: CGSize, in rect: CGRect) -> CGRect {
        CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
