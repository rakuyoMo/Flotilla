import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderPanelTests

/// 面板窗口：材质、边缘线、阴影与白色文字都按深色外观实测，系统切到浅色外观时面板也必须保持深色
@MainActor
struct FolderPanelTests {
    /// 面板固定深色外观，不跟随系统外观
    @Test
    func panelUsesDarkAppearance() {
        let panel = FolderPanel()

        #expect(panel.appearance?.name == .darkAqua)
    }
}
