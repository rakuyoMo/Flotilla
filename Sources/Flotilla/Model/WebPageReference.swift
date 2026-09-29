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
    /// 显示的名称：有标题用标题，没有时用网址
    var displayName: String {
        #warning("TODO: 没有标题时显示什么，按探针 29 测到的 Dock 网页 tile 规则确定")
        return title ?? url.absoluteString
    }

    /// 网页的图标：网址文件（`.webloc`）的图标
    var icon: NSImage {
        #warning("TODO: 网页图标按探针 29 测到的 Dock 网页 tile 图标确定")

        let webInternetLocation = UTType("com.apple.web-internet-location") ?? .internetLocation

        return NSWorkspace.shared.icon(for: webInternetLocation)
    }
}
