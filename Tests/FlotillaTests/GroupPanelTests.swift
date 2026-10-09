import AppKit
import Testing

@testable import Flotilla

// MARK: - GroupPanelTests

/// 面板窗口跟随系统外观：原生弹窗在浅色外观下是浅色材质、黑色文字，深色外观下是深色材质、白色文字
@MainActor
struct GroupPanelTests {
    /// 面板不固定外观，材质与文字随系统切换深浅
    @Test
    func panelFollowsSystemAppearance() {
        let panel = GroupPanel()

        #expect(panel.appearance == nil)
    }

    /// 标题与名称的颜色按视图外观解析：深色为白色、不透明度 0.95，浅色为黑色、不透明度 0.85
    @Test
    func textColorResolvesPerAppearance() throws {
        let dark = try #require(resolvedTextColor(in: .darkAqua))
        let light = try #require(resolvedTextColor(in: .aqua))

        #expect(dark.redComponent == 1)
        #expect(abs(dark.alphaComponent - 0.95) < 0.001)

        #expect(light.redComponent == 0)
        #expect(abs(light.alphaComponent - 0.85) < 0.001)
    }

    /// 高对比度、vibrant 等外观变体按最接近的深色或浅色取值
    @Test
    func appearanceVariantsMapToNearestBase() throws {
        let highContrastDark = try #require(NSAppearance(named: .accessibilityHighContrastDarkAqua))
        let vibrantLight = try #require(NSAppearance(named: .vibrantLight))

        #expect(GroupPanelAppearance(highContrastDark) == .dark)
        #expect(GroupPanelAppearance(vibrantLight) == .light)
    }
}

// MARK: - Private

extension GroupPanelTests {
    /// 在指定外观下把动态文字颜色解析成 sRGB 分量
    private func resolvedTextColor(in name: NSAppearance.Name) -> NSColor? {
        var resolved: NSColor? = nil

        NSAppearance(named: name)?.performAsCurrentDrawingAppearance {
            resolved = GroupPanelAppearance.dynamicTextColor.usingColorSpace(.sRGB)
        }

        return resolved
    }
}
