import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderGridItemViewTests

/// 单元格的按下与抬起，以及“在访达中打开”的画法，都按原生叠放实测：
/// 各项拖出单元格就取消；“在访达中打开”按下后保持到抬起、在哪里抬起都触发，图标叠加到面板材质上
@MainActor
struct FolderGridItemViewTests {
    /// 单元格内的一点，窗口坐标
    private let inside = CGPoint(x: 64, y: 64)

    /// 单元格与面板之外的一点，窗口坐标
    private let outside = CGPoint(x: 360, y: 360)

    /// 各项：拖出单元格后恢复平常的样子，在单元格外抬起不触发
    @Test
    func itemCancelsWhenDraggedOut() throws {
        var clickCount = 0

        let (window, itemView) = makeItemView(style: .item) {
            clickCount += 1
        }

        let normalImage = try displayedImage(of: itemView)

        itemView.mouseDown(with: try mouseEvent(.leftMouseDown, at: inside, in: window))

        #expect(try displayedImage(of: itemView) !== normalImage)

        itemView.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: outside, in: window))

        #expect(try displayedImage(of: itemView) === normalImage)

        itemView.mouseUp(with: try mouseEvent(.leftMouseUp, at: outside, in: window))

        #expect(clickCount == 0)
    }

    /// “在访达中打开”：拖出单元格、拖出面板仍是按下的样子，在那里抬起也触发一次
    @Test
    func openInFinderTriggersWhereverReleased() throws {
        var clickCount = 0

        let (window, itemView) = makeItemView(style: .openInFinder) {
            clickCount += 1
        }

        let normalImage = try displayedImage(of: itemView)

        itemView.mouseDown(with: try mouseEvent(.leftMouseDown, at: inside, in: window))

        let pressedImage = try displayedImage(of: itemView)

        #expect(pressedImage !== normalImage)

        itemView.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: outside, in: window))

        #expect(try displayedImage(of: itemView) === pressedImage)

        itemView.mouseUp(with: try mouseEvent(.leftMouseUp, at: outside, in: window))

        #expect(clickCount == 1)
        #expect(try displayedImage(of: itemView) === normalImage)
    }

    /// “在访达中打开”的图标：深色以 plus-lighter 合成，平时每个通道加 124、按下加 50；
    /// 浅色以 plus-darker 合成，平时减 127、按下减 194
    @Test
    func openInFinderIconBlendsWithMaterial() throws {
        let (window, itemView) = makeItemView(style: .openInFinder) { }
        let imageView = try #require(itemView.subviews.compactMap { $0 as? NSImageView }.first)

        let cases: [(NSAppearance.Name, String, normal: Int, pressed: Int)] = [
            (.darkAqua, "plusL", 124, 50),
            (.aqua, "plusD", 255 - 127, 255 - 194),
        ]

        for (name, filter, normal, pressed) in cases {
            itemView.appearance = NSAppearance(named: name)

            let normalGray = try centerGray(of: displayedImage(of: itemView))

            #expect(imageView.layer?.compositingFilter as? String == filter)
            #expect(normalGray == normal)

            itemView.mouseDown(with: try mouseEvent(.leftMouseDown, at: inside, in: window))

            let pressedGray = try centerGray(of: displayedImage(of: itemView))

            #expect(pressedGray == pressed)

            itemView.mouseUp(with: try mouseEvent(.leftMouseUp, at: inside, in: window))
        }
    }

    /// “在访达中打开”的图标按 100 pt 摆放，中心与其它格的图标相同：原生圆圈外径 64 pt
    @Test
    func openInFinderIconIsSmallerAndCentered() throws {
        let (window, itemView) = makeItemView(style: .openInFinder) { }
        let imageView = try #require(itemView.subviews.compactMap { $0 as? NSImageView }.first)

        // 窗口要活到排版结束，单元格才一直有父视图
        withExtendedLifetime(window) {
            itemView.layoutSubtreeIfNeeded()
        }

        #expect(imageView.frame.size == CGSize(width: 100, height: 100))
        #expect(CGPoint(x: imageView.frame.midX, y: imageView.frame.midY) == itemView.iconCenter)
    }
}

// MARK: - Private

extension FolderGridItemViewTests {
    /// 放在窗口左下角的单元格；图标是 128 pt 的不透明黑色方块，着色后整张图都是着上的颜色
    private func makeItemView(
        style: FolderGridItemStyle,
        clickHandler: @escaping () -> Void
    ) -> (window: NSWindow, itemView: FolderGridItemView) {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: .borderless,
            backing: .buffered,
            defer: true
        )

        let icon = NSImage(size: CGSize(width: 128, height: 128), flipped: false) { rect in
            NSColor.black.setFill()
            rect.fill()

            return true
        }

        let itemView = FolderGridItemView(
            title: "名称",
            icon: icon,
            style: style,
            clickHandler: clickHandler
        )

        itemView.frame = CGRect(
            x: 0,
            y: 0,
            width: FolderPanelMetrics.cellSize,
            height: FolderPanelMetrics.cellSize
        )

        window.contentView?.addSubview(itemView)

        return (window, itemView)
    }

    /// 窗口里某一点的鼠标事件
    private func mouseEvent(
        _ type: NSEvent.EventType,
        at location: CGPoint,
        in window: NSWindow
    ) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    /// 单元格当前显示的图
    private func displayedImage(of itemView: FolderGridItemView) throws -> NSImage {
        let imageView = try #require(itemView.subviews.compactMap { $0 as? NSImageView }.first)

        return try #require(imageView.image)
    }

    /// 图中心像素在 sRGB 里的红色通道读数（0–255）；图标是灰色，三个通道相同
    ///
    /// 把图画进 1 × 1 的 sRGB 画布，让中心像素正好落在这一格上
    private func centerGray(of image: NSImage) throws -> Int {
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var pixel = [UInt8](repeating: 0, count: 4)

        let context = try #require(CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))

        context.draw(cgImage, in: CGRect(
            x: -CGFloat(cgImage.width / 2),
            y: -CGFloat(cgImage.height / 2),
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        ))

        return Int(pixel[0])
    }
}
