import AppKit

// Dock tile 的 stub：
// 被 Dock 启动后，以不激活任何 App 的方式打开 `flotilla://` URL，等到结果后退出；
// 由把 App 或文件拖到 tile 上启动时，URL 里一并带上被拖的项

/// stub 的应用 delegate；`NSApplication.delegate` 是弱引用，由这里持有
let delegate = DockTileAppDelegate()

NSApplication.shared.delegate = delegate
NSApplication.shared.run()
