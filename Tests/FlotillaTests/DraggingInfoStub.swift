import AppKit

// MARK: - DraggingInfoStub

/// 只带剪贴板的拖放信息：不经真实的拖动会话，也能调用数据源的拖放校验与放下
@MainActor
final class DraggingInfoStub: NSObject, NSDraggingInfo {
    /// 拖动内容所在的剪贴板
    let draggingPasteboard: NSPasteboard

    /// 没有目标窗口
    let draggingDestinationWindow: NSWindow? = nil

    /// 外部拖入按拷贝处理
    let draggingSourceOperationMask = NSDragOperation.copy

    /// 拖动位置，数据源不读取
    let draggingLocation = NSPoint.zero

    /// 拖动图像的位置，数据源不读取
    let draggedImageLocation = NSPoint.zero

    /// 没有拖动来源：来自其它 App
    let draggingSource: Any? = nil

    /// 拖动会话编号，数据源不读取
    let draggingSequenceNumber = 0

    /// 拖动图像的排列方式，数据源不读取
    var draggingFormation = NSDraggingFormation.default

    /// 放下后是否把图像动画到落点，数据源不读取
    var animatesToDestination = false

    /// 可放下的项数，数据源不读取
    var numberOfValidItemsForDrop = 0

    /// 弹簧加载的高亮，数据源不读取
    let springLoadingHighlight = NSSpringLoadingHighlight.none

    /// 已废弃的拖动图像，数据源不读取
    nonisolated var draggedImage: NSImage? {
        nil
    }

    /// 包装一块剪贴板
    /// - Parameter pasteboard: 拖动内容所在的剪贴板
    init(pasteboard: NSPasteboard) {
        draggingPasteboard = pasteboard
    }

    /// 数据源不移动拖动图像
    func slideDraggedImage(to _: NSPoint) { }

    /// 数据源不逐项修改拖动图像
    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions = [],
        for _: NSView?,
        classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using _: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) { }

    /// 数据源不使用弹簧加载
    func resetSpringLoading() { }
}
