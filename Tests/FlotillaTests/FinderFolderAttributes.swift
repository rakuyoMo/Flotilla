import Foundation

// MARK: - FinderFolderAttributes

/// 测试里给临时目录里的文件夹写上访达的外观：直接写扩展属性，自定义图标的 `Icon\r` 另外建文件
///
/// 不用 `NSURL` 的 `tagNamesKey` 打标签：它写进去的标签没有颜色号，是无色的
enum FinderFolderAttributes {
    /// 标签在扩展属性里的名字
    private static let tagsAttributeName = "com.apple.metadata:_kMDItemUserTags"

    /// emoji 与符号在扩展属性里的名字
    private static let symbolOrEmojiAttributeName = "com.apple.icon.folder#S"

    /// Finder 信息在扩展属性里的名字
    private static let finderInfoAttributeName = "com.apple.FinderInfo"

    /// 写上标签：每项是 “名称\n颜色号”，颜色号 1–7，0 或不写为无色；传空数组时删掉标签
    /// - Parameters:
    ///   - tags: 标签，按顺序
    ///   - url: 文件夹的 URL
    static func setTags(_ tags: [String], of url: URL) throws {
        guard !tags.isEmpty else {
            removexattr(url.path(percentEncoded: false), tagsAttributeName, 0)
            return
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: tags,
            format: .binary,
            options: 0
        )

        try setAttribute(tagsAttributeName, to: data, of: url)
    }

    /// 写上 emoji 或符号，如 `{"emoji":"🍕"}`、`{"sym":"star.fill"}`
    /// - Parameters:
    ///   - json: 扩展属性的内容
    ///   - url: 文件夹的 URL
    static func setSymbolOrEmoji(_ json: String, of url: URL) throws {
        try setAttribute(symbolOrEmojiAttributeName, to: Data(json.utf8), of: url)
    }

    /// 在 Finder 信息里置上 kHasCustomIcon：32 字节，偏移 8 起的 2 字节是大端的 Finder flags，置 `0x0400`
    ///
    /// 访达给文件夹加 emoji 或符号时就是这样，文件夹里不放 `Icon\r`
    /// - Parameter url: 文件夹的 URL
    static func setCustomIconFlag(of url: URL) throws {
        var finderInfo = [UInt8](repeating: 0, count: 32)

        finderInfo[8] = 0x04

        try setAttribute(finderInfoAttributeName, to: Data(finderInfo), of: url)
    }

    /// 在文件夹里放一个空的 `Icon\r`：换过自定义图标的文件夹里存放图标的文件
    /// - Parameter url: 文件夹的 URL
    static func addCustomIconFile(to url: URL) throws {
        try Data().write(to: url.appending(path: "Icon\r"))
    }

    /// 写一个扩展属性，失败时抛出 `POSIXError`
    private static func setAttribute(_ name: String, to data: Data, of url: URL) throws {
        let result = data.withUnsafeBytes {
            setxattr(
                url.path(percentEncoded: false),
                name,
                $0.baseAddress,
                data.count,
                0,
                0
            )
        }

        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
