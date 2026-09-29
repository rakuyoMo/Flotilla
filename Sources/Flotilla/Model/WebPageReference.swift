import AppKit
import UniformTypeIdentifiers

// MARK: - WebPageReference

/// 对一个网页的引用：`http` 或 `https` 网址，连同加入时浏览器给出的网页标题
struct WebPageReference: Codable, Hashable, Identifiable {
    /// 这一项的唯一标识；同一个网页放进不同文件夹时各有各的 id
    let id: UUID

    /// 网页的网址
    let url: URL

    /// 加入时浏览器给出的网页标题；浏览器没给标题，或给的是空白时为 nil
    let title: String?
}

// MARK: - Display

extension WebPageReference {
    /// 所有网页共用的图标，只加载一次
    @MainActor
    private static let sharedIcon = makeIcon()

    /// 显示的名称：有标题用标题，没有时用网址
    var displayName: String {
        title ?? url.absoluteString
    }

    /// 网页的图标：与 Dock 右侧网页 tile 相同的蓝色地球
    @MainActor
    var icon: NSImage {
        Self.sharedIcon
    }
}

// MARK: - Private

extension WebPageReference {
    /// 读取 Dock 右侧网页 tile 用的 `BookmarkIcon.icns`；读不到时退回网址文件（`.webloc`）的图标
    ///
    /// 实测（macOS 27）`NSWorkspace` 按 `com.apple.web-internet-location`、`public.url` 等类型取到的图标都不是它
    private static func makeIcon() -> NSImage {
        let bookmarkIconURL = URL(
            filePath: "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/BookmarkIcon.icns"
        )

        if let icon = NSImage(contentsOf: bookmarkIconURL) {
            return icon
        }

        let webInternetLocation = UTType("com.apple.web-internet-location") ?? .internetLocation

        return NSWorkspace.shared.icon(for: webInternetLocation)
    }
}
