import AppKit

// MARK: - FolderPanelDecorationView

/// 只承载装饰图层（阴影、边缘线）的视图：铺满面板的一层，不参与点击，鼠标事件交给它下面的内容
@MainActor
final class FolderPanelDecorationView: NSView {
    /// 创建承载图层的视图；图层由调用方添加到 `layer` 上
    init() {
        super.init(frame: .zero)

        // 先设置图层再打开 wantsLayer，成为由自己管理子图层的 layer-hosting 视图
        layer = CALayer()
        wantsLayer = true
    }

    /// 装饰视图完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("不支持从归档解码")
    }

    /// 从不成为点击目标
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}
