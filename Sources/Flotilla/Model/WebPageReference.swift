import AppKit
import UniformTypeIdentifiers

// MARK: - WebPageReference

/// 对一个网页的引用：`http` 或 `https` 网址，连同网页的标题
struct WebPageReference: Codable, Hashable, Identifiable {
    /// 这一项的唯一标识；同一个网页放进不同组时各有各的 id
    let id: UUID

    /// 网页的网址
    let url: URL

    /// 网页的标题：从浏览器拖入时浏览器给出的，或网页提示框（“添加网页…” 与 “编辑…”）里填写、自动获取到的；都没有时为 nil
    let title: String?
}

// MARK: - Display

extension WebPageReference {
    /// 所有网页共用的图标，只加载一次
    @MainActor
    private static let sharedIcon = makeIcon()

    /// 显示的名称：有标题用标题，没有时用显示的网址
    var displayName: String {
        title ?? displayAddress
    }

    /// 显示的网址：`url.absoluteString` 里百分号编码的中文等可见非 ASCII 字符还原成文字，其余照原样（需求 34）
    ///
    /// 照原样的编码有三种：
    /// - ASCII 字符的编码，如 `%20`、`%2F`：还原后会改变网址的含义，也不能再原样解析回来
    /// - 不是合法 UTF-8 的编码，如 GBK 编码的 `%B9%E9`
    /// - 还原出空白、控制或格式字符的编码，如 U+3000、U+200B、U+202E：显示出来看不见，或会打乱文字的顺序
    var displayAddress: String {
        url.absoluteString.replacing(/(?:%[0-9A-Fa-f]{2})+/) {
            Self.decodingVisibleCharacters(in: $0.output)
        }
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

    /// 把一段连续的百分号编码里能还原成可见非 ASCII 字符的 UTF-8 字节序列还原成文字，其余各段照原样
    /// - Parameter run: 一段连续的百分号编码，如 `%E5%BD%92%20`；十六进制大写、小写都可能
    private static func decodingVisibleCharacters(in run: Substring) -> String {
        // 每段是两位十六进制：照原样放回时保留原来的大小写
        let hexPairs = run.split(separator: "%")
        let bytes = hexPairs.compactMap { UInt8($0, radix: 16) }

        var text = ""
        var index = bytes.startIndex

        while index < bytes.endIndex {
            // 从这个字节起是一个可见的非 ASCII 字符：换成文字，跳过它的各个字节
            if let scalar = visibleScalar(startingAt: index, in: bytes) {
                text.unicodeScalars.append(scalar)
                index += UTF8.width(scalar)
                continue
            }

            // 其余的一次放回一个字节：不合法的序列后面可能紧跟着合法的
            text += "%\(hexPairs[index])"
            index += 1
        }

        return text
    }

    /// 从第 index 个字节起按 UTF-8 解码出的字符；是 ASCII、不是合法 UTF-8，或是空白、控制、格式字符时为 nil
    /// - Parameters:
    ///   - index: 起始字节的下标
    ///   - bytes: 一段连续的百分号编码表示的字节
    private static func visibleScalar(startingAt index: Int, in bytes: [UInt8]) -> Unicode.Scalar? {
        var iterator = bytes[index...].makeIterator()
        var decoder = UTF8()

        guard
            case .scalarValue(let scalar) = decoder.decode(&iterator),
            !scalar.isASCII
        else {
            return nil
        }

        switch scalar.properties.generalCategory {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator, .control, .format:
            return nil

        default:
            return scalar
        }
    }
}
