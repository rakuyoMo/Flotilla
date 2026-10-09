import AppKit

// MARK: - GroupPanelLabel

/// 面板与 “移除” 气泡里的文字标签：关闭字体平滑后绘制
///
/// 原生弹窗与程序坞 “移除” 的文字都没有字体平滑；开着平滑时，同样字号与字重的笔画在屏上明显更粗
@MainActor
final class GroupPanelLabel: NSTextField {
    /// 关闭字体平滑，再按常规方式绘制
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)

        super.draw(dirtyRect)
    }
}
