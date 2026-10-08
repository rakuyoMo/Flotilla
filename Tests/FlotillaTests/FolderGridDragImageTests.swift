import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderGridDragImageTests

/// 多显示器时把一项拖到另一块屏幕上：拖动图像的窗口要跟到图标中心所在的屏幕，否则图标被窗口裁掉，
/// 拖动仍在继续、松开照样删除，用户却没了拖动反馈；落回面板所在的屏幕时，落定从画面上的当前位置开始，不跳。
/// 拖动图像要与格里的图标一样清晰，落定途中也不被面板盖住
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
