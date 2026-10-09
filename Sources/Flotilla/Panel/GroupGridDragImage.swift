import AppKit
import QuartzCore

// MARK: - GroupGridDragImage

/// 拖动图像：拖动网格里的一项时跟随鼠标的图标，与格里的图标同样大小、不透明、不压暗、不带名称
///
/// 放在单独的无边框窗口里，出了面板窗口也看得见：窗口铺满图标中心所在的那块屏幕，图标是其中的一个图层，
/// 跟随鼠标时只移动图层，图标中心移到另一块屏幕上时窗口换到那块屏幕；落进目标格时按展开动画的时长与曲线移动，
/// 落回原来的格时按程序坞里图标飞回原位的时长与曲线移动。
/// 窗口在拖动图像的层级，高于面板；不接收鼠标事件、不成为 key，也不激活 Flotilla（需求 6）
///
/// 图标上方可以浮出 “移除”：气泡是窗口里图标之上的视图，位置跟着图标，跟随鼠标、换屏幕与落定都一起走，不画进图标的位图；
/// 贴近屏幕边时收在这块屏幕之内
///
/// 窗口只铺一块屏幕，不铺所有屏幕的并集：“显示器具有单独的空间” 打开（系统默认）时，一个窗口只显示在一块屏幕上
@MainActor
final class GroupGridDragImage {
    /// 图标上方浮出的 “移除”
    let removeLabel: GroupGridRemoveLabel

    /// 承载图标的窗口：透明、点击穿透，层级是拖动图像的层级
    ///
    /// 与系统拖放的拖动图像同一层级，高于面板：在面板里抬起时系统把面板排到同层级的最前，层级相同就会盖住落定中的图标
    private let window: NSPanel

    /// 各块屏幕的 frame，开始拖动时取一次：拖动中屏幕参数变化会收起面板，拖动随之作废
    private let screenFrames: [CGRect]

    /// 窗口的内容视图：铺满窗口、不翻转，图标在下，“移除” 的气泡在上；删除时整体在原地淡出
    private let contentView = NSView()

    /// 图标图层的容器：大小为零、不裁剪，位置把屏幕坐标平移成窗口坐标，落定途中另加目标格移过的距离
    ///
    /// 落定动画在容器里进行：窗口换屏幕、落定途中目标格移动，都只平移容器，进行中的动画不受影响
    private let containerLayer = CALayer()

    /// 显示图标的图层，位置即图标中心
    private let iconLayer = CALayer()

    /// 图标中心，AppKit 屏幕坐标，按图层与窗口的位置换算；落定时是落点，即落定之后的位置
    var iconCenter: CGPoint {
        screenPoint(ofContainerPoint: iconLayer.position)
    }

    /// 窗口的 frame：图标中心所在的那块屏幕
    var windowFrame: CGRect {
        window.frame
    }

    /// 窗口的层级：拖动图像的层级，高于面板
    var windowLevel: NSWindow.Level {
        window.level
    }

    /// 图标图层显示的位图：图标按格里图标的大小与屏幕倍数画出；没有位图时为 nil
    var iconImage: CGImage? {
        guard let contents = iconLayer.contents else { return nil }

        let object = contents as AnyObject

        guard CFGetTypeID(object) == CGImage.typeID else { return nil }

        return unsafeDowncast(object, to: CGImage.self)
    }

    /// 落定动画开始时画面上的图标中心，AppKit 屏幕坐标，按图层与窗口的位置换算；不在落定动画中时为 nil
    var landingStart: CGPoint? {
        guard
            let animation = iconLayer.animation(forKey: "position") as? CABasicAnimation,
            let start = (animation.fromValue as? NSValue)?.pointValue
        else {
            return nil
        }

        return screenPoint(ofContainerPoint: start)
    }

    /// 落定动画的时长；不在落定动画中时为 nil
    var landingDuration: CFTimeInterval? {
        iconLayer.animation(forKey: "position")?.duration
    }

    /// 进行中的原地淡出的时长；不在淡出中时为 nil
    var fadeOutDuration: CFTimeInterval? {
        contentView.layer?.animation(forKey: "opacity")?.duration
    }

    /// “移除” 气泡的 frame（主体加小尖），AppKit 屏幕坐标；没有浮出时同样有值，只是看不见
    var removeLabelFrame: CGRect {
        removeLabel.view.frame.offsetBy(
            dx: window.frame.minX,
            dy: window.frame.minY
        )
    }

    /// 创建拖动图像；创建后还看不见，要 `show(over:)`
    /// - Parameters:
    ///   - icon: 这一项的图标，不压暗
    ///   - iconCenter: 图标中心，AppKit 屏幕坐标
    ///   - screenFrames: 各块屏幕的 frame；窗口铺满图标中心所在的那块，不在任何一块上时先不占地方
    ///   - scale: 屏幕的倍数：图标按格里图标的大小乘以倍数的像素画出
    init(
        icon: NSImage,
        iconCenter: CGPoint,
        screenFrames: [CGRect],
        scale: CGFloat
    ) {
        self.screenFrames = screenFrames
        removeLabel = GroupGridRemoveLabel(scale: scale)

        window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.draggingWindow)))

        // 与面板一样出现在每个桌面与全屏 App 之上
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]

        // 图标所在的视图托管自己的图层：容器与图标图层由这里摆放，AppKit 不改它们；
        // 托管图层的视图放不了子视图，“移除” 的气泡与它并列，排在它之上
        let iconHostView = NSView(frame: .zero)
        iconHostView.layer = CALayer()
        iconHostView.wantsLayer = true
        iconHostView.autoresizingMask = [.width, .height]
        iconHostView.layer?.addSublayer(containerLayer)

        contentView.wantsLayer = true
        contentView.addSubview(iconHostView)
        contentView.addSubview(removeLabel.view)
        window.contentView = contentView

        // 大小与格里的图标相同，位图的像素与屏上的像素一一对应
        let side = GroupPanelMetrics.iconSize

        iconLayer.contents = Self.bitmap(of: icon, side: side, scale: scale)
        iconLayer.contentsScale = scale
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)

        containerLayer.addSublayer(iconLayer)

        move(to: iconCenter)
    }

    /// 显示在面板之上：窗口的层级高于面板，面板在同层级里怎么重排都盖不住它；
    /// 面板不在屏幕上时（例如离屏的测试窗口）不显示
    /// - Parameter panel: 网格所在的面板窗口
    func show(over panel: NSWindow) {
        guard panel.isVisible else { return }

        // 排到最前但不激活 Flotilla（需求 6）
        window.orderFrontRegardless()
    }

    /// 跟随鼠标：图标中心移到给定位置，不加动画；移到另一块屏幕上时窗口换到那块屏幕
    /// - Parameter center: 图标中心，AppKit 屏幕坐标
    func move(to center: CGPoint) {
        moveWindow(toScreenContaining: center)
        place(center)
    }

    /// 落进目标格：从当前画面移到给定位置，时长与曲线沿用展开动画
    ///
    /// 目标格不在窗口所在的屏幕上时，窗口先换到目标格所在的屏幕，再从画面上的当前位置开始移动
    /// - Parameter center: 目标格的图标中心，AppKit 屏幕坐标
    func land(at center: CGPoint) {
        moveForLanding(
            to: center,
            animation: GroupGridDragAnimation.movePosition(of:from:)
        )
    }

    /// 落回原来的格：从当前画面飞回给定位置，两头慢、中间快，与程序坞里提前松手时图标飞回原位相同
    ///
    /// 原来的格不在窗口所在的屏幕上时，窗口先换到那块屏幕，再从画面上的当前位置开始移动
    /// - Parameter center: 原来那一格的图标中心，AppKit 屏幕坐标
    func landInOriginalCell(at center: CGPoint) {
        moveForLanding(
            to: center,
            animation: GroupGridDragAnimation.returnPosition(of:from:)
        )
    }

    /// 落定途中目标格移动了（网格滚动）：落点换到给定位置，不加动画
    ///
    /// 只平移容器：落定动画照旧进行、按松开时的时长收尾，收尾时图标正好在新的落点上
    /// - Parameter center: 目标格现在的图标中心，AppKit 屏幕坐标
    func moveLandingPoint(to center: CGPoint) {
        let current = iconCenter

        shiftContainer(by: CGVector(
            dx: center.x - current.x,
            dy: center.y - current.y
        ))
    }

    /// 删除时：图标连同 “移除” 在原地淡出，匀速、只变不透明度，淡完关掉
    ///
    /// 按时长收尾，不等 Core Animation 的完成回调：锁屏、显示器休眠时回调可能一直不来。
    /// 收尾的任务自己持有拖动图像：删除已经完成，淡出不随面板收起或重建中断
    func fadeOut() {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0
        animation.duration = GroupPanelMetrics.removeFadeOutDuration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)

        contentView.alphaValue = 0
        contentView.layer?.add(animation, forKey: "opacity")

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(GroupPanelMetrics.removeFadeOutDuration))

            self.close()
        }
    }

    /// 立即消失；可以重复调用
    func close() {
        iconLayer.removeAllAnimations()
        window.orderOut(nil)
    }
}

// MARK: - Private

extension GroupGridDragImage {
    /// 窗口换到给定一点所在的屏幕上；这一点不在任何屏幕上（屏幕之间的空隙）、或窗口已在那块屏幕上时不动
    ///
    /// 容器按新旧窗口原点之差反向平移：画面上的图标位置不变，进行中的动画不受影响
    private func moveWindow(toScreenContaining point: CGPoint) {
        guard
            let screenFrame = screenFrames.first(where: { $0.contains(point) }),
            screenFrame != window.frame
        else {
            return
        }

        shiftContainer(by: CGVector(
            dx: window.frame.minX - screenFrame.minX,
            dy: window.frame.minY - screenFrame.minY
        ))

        window.setFrame(screenFrame, display: false)
    }

    /// 移到落点：图标与 “移除” 的模型位置先到位，再按给定的动画从画面上的当前位置移过去
    ///
    /// “移除” 这时至多还在淡出，它的位移叠加在模型位置上：落定途中容器平移、气泡的模型位置随之改变，
    /// 它仍跟着图标，动画进度不变
    /// - Parameters:
    ///   - center: 落点的图标中心，AppKit 屏幕坐标
    ///   - animation: 位置动画，给图层加上从画面上的起点到模型位置的移动
    private func moveForLanding(
        to center: CGPoint,
        animation: @MainActor (CALayer, CGPoint) -> Void
    ) {
        // 起点取在容器里：换屏幕时容器随之平移，起点换算到新窗口的坐标后仍是画面上的当前位置
        let start = iconLayer.presentation()?.position ?? iconLayer.position

        // 气泡的起点按屏幕坐标记下：落定之前它没有位移动画，frame 就是画面上的位置
        let labelStart = removeLabelFrame.origin

        moveWindow(toScreenContaining: center)
        place(center)

        animation(iconLayer, start)

        guard
            let labelLayer = removeLabel.view.layer,
            let labelAnimation = iconLayer.animation(forKey: "position")?.copy() as? CABasicAnimation
        else {
            return
        }

        let labelEnd = removeLabelFrame.origin

        // 照搬图标的动画，时长、曲线与开始的时刻都相同；
        // 改成叠加的位移：从气泡的起点与落点之差回到零。离屏幕边远时它就是图标的起点与落点之差，
        // 画面上始终与图标保持落定之后的相对位置；贴近屏幕边时起点与落点各自收在屏幕之内，途中在两者之间移动
        labelAnimation.isAdditive = true

        labelAnimation.fromValue = NSValue(point: CGPoint(
            x: labelStart.x - labelEnd.x,
            y: labelStart.y - labelEnd.y
        ))

        labelAnimation.toValue = NSValue(point: .zero)

        labelLayer.add(labelAnimation, forKey: "position")
    }

    /// 把图标图层的模型位置设到图标中心，关掉独立图层默认的隐式动画；“移除” 的气泡随之摆到图标上方
    private func place(_ center: CGPoint) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        iconLayer.position = containerPoint(ofScreenPoint: center)

        CATransaction.commit()

        placeRemoveLabel()
    }

    /// 平移容器，关掉独立图层默认的隐式动画：其中的图标连同进行中的动画一起平移；“移除” 的气泡随之平移
    private func shiftContainer(by offset: CGVector) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        containerLayer.position = CGPoint(
            x: containerLayer.position.x + offset.dx,
            y: containerLayer.position.y + offset.dy
        )

        CATransaction.commit()

        placeRemoveLabel()
    }

    /// “移除” 的气泡摆到图标上方：以图标中心水平居中，主体底边在图标画布顶边之上 `removeLabelSpacing`；
    /// 贴近屏幕边时收在窗口之内，即拖动图像所在的这块屏幕之内
    private func placeRemoveLabel() {
        // 图标中心的窗口坐标：容器里的位置加上容器的位置
        let center = CGPoint(
            x: iconLayer.position.x + containerLayer.position.x,
            y: iconLayer.position.y + containerLayer.position.y
        )

        let bodyBottom = center.y + GroupPanelMetrics.iconSize / 2 + GroupPanelMetrics.removeLabelSpacing
        let size = removeLabel.view.frame.size

        let origin = CGPoint(
            x: center.x - size.width / 2,
            y: bodyBottom - removeLabel.bodyFrame.minY
        )

        // 哪一侧越出窗口，就往里收到贴着那条屏幕边，例如图标中心贴近顶边时往下收。
        // 浮出之后松开就删除，气泡落到屏幕之外的话，用户看不到这个提示
        let bounds = contentView.bounds

        removeLabel.view.setFrameOrigin(CGPoint(
            x: min(max(origin.x, bounds.minX), bounds.maxX - size.width),
            y: min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        ))
    }

    /// 容器里的一点换算到 AppKit 屏幕坐标
    ///
    /// 内容视图与图标所在的视图都铺满窗口、不翻转，容器大小为零：容器里的点加上容器的位置即窗口坐标，再加上窗口原点即屏幕坐标
    private func screenPoint(ofContainerPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x + containerLayer.position.x + window.frame.minX,
            y: point.y + containerLayer.position.y + window.frame.minY
        )
    }

    /// AppKit 屏幕坐标里的一点换算到容器里，与 `screenPoint(ofContainerPoint:)` 互逆
    private func containerPoint(ofScreenPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x - containerLayer.position.x - window.frame.minX,
            y: point.y - containerLayer.position.y - window.frame.minY
        )
    }
}

// MARK: - Helpers

extension GroupGridDragImage {
    /// 图标按显示的大小画出、按屏幕倍数的像素取出的位图，与格里的图标一样清晰；画不出时为 nil
    ///
    /// 画进显示的大小，`draw(in:)` 才按屏上的像素挑图标里最合适的表示；
    /// 图标的 `layerContents(forContentsScale:)` 按图标自己的 size（`NSWorkspace` 的图标是 32 × 32 pt）取图，放大后发糊
    /// - Parameters:
    ///   - icon: 这一项的图标
    ///   - side: 显示的边长
    ///   - scale: 屏幕的倍数
    private static func bitmap(of icon: NSImage, side: CGFloat, scale: CGFloat) -> CGImage? {
        let image = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            icon.draw(in: rect)

            return true
        }

        // 按屏幕倍数的变换取出：位图的像素是显示的边长乘以倍数
        var rect = CGRect(x: 0, y: 0, width: side, height: side)

        return image.cgImage(
            forProposedRect: &rect,
            context: nil,
            hints: [.ctm: AffineTransform(scale: scale)]
        )
    }
}
