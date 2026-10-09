import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderGridDragImageTests

/// 多显示器时把一项拖到另一块屏幕上：拖动图像的窗口要跟到图标中心所在的屏幕，否则图标被窗口裁掉，
/// 拖动仍在继续、松开照样删除，用户却没了拖动反馈；落回面板所在的屏幕时，落定从画面上的当前位置开始，不跳。
/// 拖动图像要与格里的图标一样清晰，落定途中也不被面板盖住。
/// 图标上方浮出的 “移除” 与程序坞的大小、位置、淡入淡出相同，跟着图标走，贴近屏幕边时收在屏幕之内，且不画进图标的位图；
/// 删除时在原地淡出
///
/// 两块屏幕是假的 frame：从不上屏的窗口原样接受不存在的屏幕 frame。测试里不调 `show(over:)`，窗口从不上屏
@MainActor
struct FolderGridDragImageTests {
    /// 左右并排的两块屏幕：右边一块更大、底边高出 200 pt，两块之间在右下方留有空隙
    private let screens = [
        CGRect(x: 0, y: 0, width: 1000, height: 800),
        CGRect(x: 1000, y: 200, width: 1200, height: 900),
    ]

    /// 图标中心移进第二块屏幕：窗口换成第二块，画面上的图标中心就是移到的位置
    @Test
    func windowFollowsIconCenterToAnotherScreen() {
        let image = makeImage()

        #expect(image.windowFrame == screens[0])

        image.move(to: CGPoint(x: 1500, y: 600))

        #expect(image.windowFrame == screens[1])
        #expect(image.iconCenter == CGPoint(x: 1500, y: 600))
    }

    /// 图标中心移进两块屏幕之间的空隙：窗口不动，图标照旧跟随
    @Test
    func windowStaysWhenIconCenterIsBetweenScreens() {
        let image = makeImage()

        image.move(to: CGPoint(x: 1500, y: 600))
        image.move(to: CGPoint(x: 1100, y: 100))

        #expect(image.windowFrame == screens[1])
        #expect(image.iconCenter == CGPoint(x: 1100, y: 100))
    }

    /// 在第二块屏幕上松开、落进第一块屏幕上的目标格：窗口回到第一块，落定动画从画面上的当前位置开始
    @Test
    func landingOnAnotherScreenStartsFromCurrentPosition() {
        let image = makeImage()

        image.move(to: CGPoint(x: 1500, y: 600))
        image.land(at: CGPoint(x: 300, y: 400))

        #expect(image.windowFrame == screens[0])
        #expect(image.landingStart == CGPoint(x: 1500, y: 600))
        #expect(image.iconCenter == CGPoint(x: 300, y: 400))
    }

    /// 图标的 size 比格里的图标小（`NSWorkspace` 的图标是 32 × 32 pt）：拖动图像按格里图标的大小与屏幕倍数取图，
    /// 按图标自己的 size 取图再放大到格里的大小，就比格里的图标糊
    @Test(arguments: [1, 2] as [CGFloat])
    func iconBitmapMatchesDisplayedSizeAndScale(scale: CGFloat) throws {
        let icon = try smallIconWithLargeRepresentation()

        let image = FolderGridDragImage(
            icon: icon,
            iconCenter: CGPoint(x: 300, y: 400),
            screenFrames: screens,
            scale: scale
        )

        let bitmap = try #require(image.iconImage)
        let pixels = Int(FolderPanelMetrics.iconSize * scale)

        #expect(bitmap.width == pixels)
        #expect(bitmap.height == pixels)
    }

    /// 在面板里抬起时系统把面板排到同层级的最前：拖动图像的层级要高于面板，落定途中才不被面板盖住
    @Test
    func windowLevelIsAbovePanel() {
        let image = makeImage()

        #expect(image.windowLevel.rawValue > FolderPanel().level.rawValue)
    }

    /// “移除” 要等开始拖动满 0.5 s、鼠标出了它的边界才浮出：刚开始拖动时没有它
    @Test
    func removeLabelIsHiddenAtFirst() {
        #expect(!makeImage().removeLabel.isShowing)
    }

    /// 浮出的 “移除” 与程序坞的同样大小：主体 26 pt 高、宽是文字宽加左右各 14 pt，主体下面是 6 pt 高的小尖；
    /// 位置也相同：以图标中心水平居中，主体底边在图标画布顶边之上 5 pt，看得出说的是这个图标。
    /// 文字是 `panel.remove`：测试进程读不到 `.lproj` 里的译文，文字就是键名
    @Test
    func removeLabelMatchesDockGeometry() {
        let image = makeImage()
        let label = image.removeLabel
        let frame = image.removeLabelFrame

        let textWidth = NSAttributedString(
            string: "panel.remove",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        ).size().width

        let bodyWidth = ceil(textWidth) + 28

        #expect(label.text == "panel.remove")
        #expect(label.bodyFrame == CGRect(x: 0, y: 6, width: bodyWidth, height: 26))
        #expect(frame.size == CGSize(width: bodyWidth, height: 32))
        #expect(frame.midX == image.iconCenter.x)
        #expect(frame.minY + label.bodyFrame.minY == image.iconCenter.y + 101 / 2 + 5)
    }

    /// 文字关闭字体平滑，与程序坞同样粗细：程序坞的 “移除” 没有字体平滑，开着平滑时同样字号与字重的笔画明显更粗
    @Test
    func removeLabelTextIsNotSmoothed() {
        let label = makeImage().removeLabel
        let textFields = label.view.subviews.compactMap { $0 as? NSTextField }

        #expect(textFields.count == 1)
        #expect(textFields.allSatisfy { $0 is FolderPanelLabel })
    }

    /// “移除” 淡入、淡出各 0.25 s，只变不透明度：按 2–98% 量约 0.2 s，与程序坞相同；
    /// 浮出与收起都不是一下子出现或消失，位置大小不变
    @Test
    func removeLabelFadesInAndOut() {
        let image = makeImage()
        let label = image.removeLabel
        let frame = image.removeLabelFrame

        label.isShowing = true

        #expect(label.isShowing)
        #expect(label.fadeDuration == 0.25)
        #expect(image.removeLabelFrame == frame)

        label.isShowing = false

        #expect(!label.isShowing)
        #expect(label.fadeDuration == 0.25)
        #expect(image.removeLabelFrame == frame)
    }

    /// “移除” 跟着图标走：图标中心移进第二块屏幕，“移除” 与图标的相对位置不变，仍在窗口里看得见
    @Test
    func removeLabelFollowsIconToAnotherScreen() {
        let image = makeImage()

        image.removeLabel.isShowing = true

        let offset = labelOffset(of: image)

        image.move(to: CGPoint(x: 1500, y: 600))

        #expect(image.windowFrame == screens[1])
        #expect(labelOffset(of: image) == offset)
        #expect(image.windowFrame.contains(image.removeLabelFrame))
    }

    /// 图标中心贴近屏幕顶边：“移除” 往下收，顶边贴着屏幕的顶边，仍以图标中心水平居中。
    /// 按固定偏移摆在图标上方的话，气泡落到屏幕之外看不见，浮出之后松开照样删除，用户却看不到提示
    @Test(arguments: [
        CGPoint(x: 300, y: 790),
        CGPoint(x: 1500, y: 1090),
    ])
    func removeLabelMovesDownAtTopEdge(iconCenter: CGPoint) {
        let image = makeImage()

        image.move(to: iconCenter)

        let frame = image.removeLabelFrame

        #expect(image.windowFrame.contains(frame))
        #expect(frame.maxY == image.windowFrame.maxY)
        #expect(frame.midX == iconCenter.x)
    }

    /// 图标中心贴近屏幕左边：“移除” 往右收，左边贴着屏幕的左边，主体底边仍在图标画布顶边之上 5 pt
    @Test(arguments: [
        CGPoint(x: 5, y: 400),
        CGPoint(x: 1005, y: 600),
    ])
    func removeLabelMovesRightAtLeftEdge(iconCenter: CGPoint) {
        let image = makeImage()

        image.move(to: iconCenter)

        let frame = image.removeLabelFrame

        #expect(image.windowFrame.contains(frame))
        #expect(frame.minX == image.windowFrame.minX)
        #expect(frame.minY + image.removeLabel.bodyFrame.minY == iconCenter.y + 101 / 2 + 5)
    }

    /// 图标中心贴近屏幕右边：“移除” 往左收，右边贴着屏幕的右边，主体底边仍在图标画布顶边之上 5 pt
    @Test(arguments: [
        CGPoint(x: 995, y: 400),
        CGPoint(x: 2195, y: 600),
    ])
    func removeLabelMovesLeftAtRightEdge(iconCenter: CGPoint) {
        let image = makeImage()

        image.move(to: iconCenter)

        let frame = image.removeLabelFrame

        #expect(image.windowFrame.contains(frame))
        #expect(frame.maxX == image.windowFrame.maxX)
        #expect(frame.minY + image.removeLabel.bodyFrame.minY == iconCenter.y + 101 / 2 + 5)
    }

    /// 图标中心在两块屏幕之间的空隙里、低于窗口所在屏幕的底边：窗口不动，“移除” 往上收，底边贴着屏幕的底边
    @Test
    func removeLabelMovesUpWhenIconIsBelowWindow() {
        let image = makeImage()

        image.move(to: CGPoint(x: 1500, y: 600))
        image.move(to: CGPoint(x: 1100, y: 100))

        let frame = image.removeLabelFrame

        #expect(image.windowFrame == screens[1])
        #expect(image.windowFrame.contains(frame))
        #expect(frame.minY == image.windowFrame.minY)
    }

    /// 飞回原来的格时 “移除” 也跟着图标走：从第二块屏幕飞回第一块，落定之后仍在图标上方；
    /// 飞回照抄程序坞，0.32 s，比落进目标格慢
    @Test
    func removeLabelFollowsIconWhenLandingInOriginalCell() {
        let image = makeImage()
        let offset = labelOffset(of: image)

        image.move(to: CGPoint(x: 1500, y: 600))
        image.landInOriginalCell(at: CGPoint(x: 300, y: 400))

        #expect(image.windowFrame == screens[0])
        #expect(image.landingStart == CGPoint(x: 1500, y: 600))
        #expect(image.landingDuration == 0.32)
        #expect(labelOffset(of: image) == offset)
    }

    /// 落定途中网格滚动、落点移动：仍在淡出的 “移除” 在落定的每一刻都与图标保持落定之后的相对位置。
    /// 与图标脱离的话，淡出中的气泡飘在别处，落定收尾时再跳回图标上方
    @Test
    func removeLabelStaysWithIconWhenLandingPointMoves() throws {
        let image = makeImage()
        let offset = labelOffset(of: image)

        // 浮出之后又收起：落定开始时 “移除” 还在淡出
        image.removeLabel.isShowing = true
        image.removeLabel.isShowing = false

        image.move(to: CGPoint(x: 600, y: 300))
        image.landInOriginalCell(at: CGPoint(x: 300, y: 400))
        image.moveLandingPoint(to: CGPoint(x: 300, y: 250))

        let animation = try #require(labelLandingAnimation(of: image))

        #expect(animation.duration == image.landingDuration)
        #expect(
            controlPoints(of: animation.timingFunction)
                == controlPoints(of: CAMediaTimingFunction(name: .easeInEaseOut))
        )

        for progress in [0, 0.25, 0.5, 0.75, 1] as [CGFloat] {
            let icon = try iconCenter(of: image, atLandingProgress: progress)
            let label = try labelOrigin(of: image, atLandingProgress: progress)

            #expect(abs(label.x - icon.x - offset.dx) < 0.001)
            #expect(abs(label.y - icon.y - offset.dy) < 0.001)
        }
    }

    /// 贴近屏幕顶边时松开、落回原来的格：淡出中的 “移除” 从收在屏幕之内的位置出发，落定的各个进度上都在窗口之内，
    /// 收尾时回到图标上方。不从画面上的位置出发的话，松开的一刻气泡跳到屏幕之外
    @Test
    func removeLabelStaysInsideScreenWhileLanding() throws {
        let image = makeImage()
        let offset = labelOffset(of: image)

        // 浮出之后又收起：落定开始时 “移除” 还在淡出
        image.removeLabel.isShowing = true
        image.removeLabel.isShowing = false

        image.move(to: CGPoint(x: 300, y: 790))

        let start = image.removeLabelFrame.origin

        image.landInOriginalCell(at: CGPoint(x: 300, y: 400))

        let size = image.removeLabelFrame.size

        for progress in [0, 0.25, 0.5, 0.75, 1] as [CGFloat] {
            let origin = try labelOrigin(of: image, atLandingProgress: progress)

            #expect(image.windowFrame.contains(CGRect(origin: origin, size: size)))
        }

        let first = try labelOrigin(of: image, atLandingProgress: 0)
        let last = try labelOrigin(of: image, atLandingProgress: 1)

        #expect(abs(first.x - start.x) < 0.001)
        #expect(abs(first.y - start.y) < 0.001)
        #expect(abs(last.x - image.iconCenter.x - offset.dx) < 0.001)
        #expect(abs(last.y - image.iconCenter.y - offset.dy) < 0.001)
    }

    /// “移除” 不画进图标的位图：位图按图标图层的大小缩放，画进去的话图标就比格里的小、偏离中心；
    /// 浮出前后位图逐字节相同
    @Test
    func removeLabelIsNotInIconImage() throws {
        let image = makeImage()
        let before = try #require(image.iconImage)

        image.removeLabel.isShowing = true

        let after = try #require(image.iconImage)

        let beforePixels = before.dataProvider?.data as Data?
        let afterPixels = after.dataProvider?.data as Data?

        #expect(after.width == before.width)
        #expect(after.height == before.height)
        #expect(afterPixels == beforePixels)
    }

    /// 删除时与程序坞相同：图标连同 “移除” 在原地淡出 0.26 s，不缩放、不移动
    @Test
    func fadeOutStaysInPlace() {
        let image = makeImage()

        image.removeLabel.isShowing = true

        let labelFrame = image.removeLabelFrame

        image.fadeOut()

        #expect(image.fadeOutDuration == 0.26)
        #expect(image.iconCenter == CGPoint(x: 300, y: 400))
        #expect(image.removeLabelFrame == labelFrame)
        #expect(image.landingStart == nil)
    }
}

// MARK: - Private

extension FolderGridDragImageTests {
    /// 图标中心在第一块屏幕上的拖动图像
    private func makeImage() -> FolderGridDragImage {
        FolderGridDragImage(
            icon: NSImage(size: CGSize(width: 101, height: 101)),
            iconCenter: CGPoint(x: 300, y: 400),
            screenFrames: screens,
            scale: 2
        )
    }

    /// “移除” 底板的原点相对图标中心的偏移
    private func labelOffset(of image: FolderGridDragImage) -> CGVector {
        let frame = image.removeLabelFrame

        return CGVector(
            dx: frame.minX - image.iconCenter.x,
            dy: frame.minY - image.iconCenter.y
        )
    }

    /// “移除” 气泡的落定动画；不在落定中时为 nil
    private func labelLandingAnimation(of image: FolderGridDragImage) -> CABasicAnimation? {
        image.removeLabel.view.layer?.animation(forKey: "position") as? CABasicAnimation
    }

    /// 落定进行到给定进度（按曲线算过之后的比例：0 是起点，1 是落点）时，画面上的图标中心，AppKit 屏幕坐标
    private func iconCenter(
        of image: FolderGridDragImage,
        atLandingProgress progress: CGFloat
    ) throws -> CGPoint {
        let start = try #require(image.landingStart)
        let end = image.iconCenter

        return CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }

    /// 落定进行到给定进度时，画面上 “移除” 底板的原点，AppKit 屏幕坐标
    ///
    /// 叠加的动画加在模型位置上，不叠加的动画取代模型位置：两种都换算成相对模型位置的位移，再加到底板的 frame 上
    private func labelOrigin(
        of image: FolderGridDragImage,
        atLandingProgress progress: CGFloat
    ) throws -> CGPoint {
        let layer = try #require(image.removeLabel.view.layer)
        let animation = try #require(labelLandingAnimation(of: image))
        let from = try #require((animation.fromValue as? NSValue)?.pointValue)
        let to = try #require((animation.toValue as? NSValue)?.pointValue)

        let value = CGPoint(
            x: from.x + (to.x - from.x) * progress,
            y: from.y + (to.y - from.y) * progress
        )

        let displacement = animation.isAdditive
            ? value
            : CGPoint(
                x: value.x - layer.position.x,
                y: value.y - layer.position.y
            )

        let frame = image.removeLabelFrame

        return CGPoint(
            x: frame.minX + displacement.x,
            y: frame.minY + displacement.y
        )
    }

    /// 动画曲线的两个控制点，依次是 x1、y1、x2、y2；没有曲线时为空
    private func controlPoints(of timingFunction: CAMediaTimingFunction?) -> [Float] {
        guard let timingFunction else { return [] }

        return [1, 2].flatMap { index -> [Float] in
            var values: [Float] = [0, 0]

            timingFunction.getControlPoint(at: index, values: &values)

            return values
        }
    }

    /// 32 × 32 pt 的图标，带一张 512 px 的表示：size 比格里的图标小，表示足够大
    private func smallIconWithLargeRepresentation() throws -> NSImage {
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 512,
                pixelsHigh: 512,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )

        let size = CGSize(width: 32, height: 32)
        representation.size = size

        let icon = NSImage(size: size)
        icon.addRepresentation(representation)

        return icon
    }
}
