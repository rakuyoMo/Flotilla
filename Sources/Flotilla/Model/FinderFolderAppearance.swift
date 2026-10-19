import Foundation

// MARK: - FinderFolderAppearance

/// 访达文件夹在访达里的外观：标签的颜色、正面的 emoji 或符号，以及是否换过自定义图标（需求 36）
///
/// macOS 26 起访达按这些给文件夹上色、画上 emoji 或符号，`NSWorkspace` 给的图标里都没有；
/// 都记在文件夹的扩展属性里，这里同步读出
struct FinderFolderAppearance: Equatable {
    /// 标签的颜色号，1–7：灰 1、绿 2、紫 3、蓝 4、黄 5、红 6、橙 7
    ///
    /// 有几个带颜色的标签时取最后一个，与访达给文件夹上的颜色相同；没有带颜色的标签时为 nil
    let tagColor: Int?

    /// 文件夹正面的 emoji 或符号：扩展属性 `com.apple.icon.folder#S` 的原始字节，没有时为 nil
    ///
    /// 只当不透明的数据比较，不解析：访达写入的完整格式没有公开
    let symbolOrEmoji: Data?

    /// 是否换过自定义图标：Finder 信息里置了 kHasCustomIcon，且文件夹里有存放图标的 `Icon\r`
    ///
    /// 换过的文件夹显示自定义图标，打了颜色标签也不着色。
    /// 访达给文件夹加 emoji 或符号时同样置上 kHasCustomIcon，但不放 `Icon\r`：这样的文件夹不算
    let hasCustomIcon: Bool

    /// 图标是否要向 QuickLook 取：macOS 26 起，没有自定义图标、带颜色或有 emoji 与符号的文件夹
    ///
    /// 其余的文件夹 `NSWorkspace` 的图标就是访达显示的样子；macOS 26 之前访达不按标签上色，也没有 emoji 与符号
    var needsQuickLookIcon: Bool {
        guard #available(macOS 26, *) else { return false }

        return !hasCustomIcon && (tagColor != nil || symbolOrEmoji != nil)
    }
}

// MARK: - Reading

extension FinderFolderAppearance {
    /// 标签在扩展属性里的名字：二进制 plist 的字符串数组，每项是 “名称\n颜色号”
    private static let tagsAttributeName = "com.apple.metadata:_kMDItemUserTags"

    /// emoji 与符号在扩展属性里的名字
    private static let symbolOrEmojiAttributeName = "com.apple.icon.folder#S"

    /// Finder 信息在扩展属性里的名字：32 字节，偏移 8 起的 2 字节是大端的 Finder flags
    private static let finderInfoAttributeName = "com.apple.FinderInfo"

    /// Finder flags 里 “有自定义图标” 的位（kHasCustomIcon）
    private static let customIconFlag: UInt16 = 0x0400

    /// 换过自定义图标的文件夹里存放图标的文件名
    private static let customIconFileName = "Icon\r"

    /// 从文件夹的扩展属性读出外观；读不到的（属性不存在、文件夹已删除、没有权限）都当作没有
    ///
    /// 标签的颜色不读 `URLResourceValues.labelNumber`：它读的是 Finder 信息里旧的标签位，只写了标签扩展属性时是 0；
    /// 自定义图标不读 `URLResourceValues.customIcon`：它对换过图标的文件夹也给 nil；
    /// `Icon\r` 按路径 `lstat`，不走 `URL` 的资源值：资源值会被缓存
    /// - Parameter url: 文件夹的 URL
    init(folderAt url: URL) {
        let path = url.path(percentEncoded: false)

        tagColor = Self.extendedAttribute(Self.tagsAttributeName, ofFileAt: path)
            .flatMap { Self.lastTagColor(in: $0) }

        symbolOrEmoji = Self.extendedAttribute(Self.symbolOrEmojiAttributeName, ofFileAt: path)

        let finderInfo = Self.extendedAttribute(Self.finderInfoAttributeName, ofFileAt: path)
        let isCustomIconFlagSet = finderInfo.map { Self.isCustomIconFlagSet(in: $0) } ?? false

        // 访达加 emoji 或符号时也置上这一位，只是不放 `Icon\r`：两样都有才是换过自定义图标
        hasCustomIcon = isCustomIconFlagSet && Self.hasCustomIconFile(inFolderAt: path)
    }
}

// MARK: - Private

extension FinderFolderAppearance {
    /// 标签里最后一个带颜色的标签的颜色号；颜色号是 0、没写颜色号的标签无色，不算
    /// - Parameter tagsData: 标签扩展属性的内容
    /// - Returns: 没有带颜色的标签、内容解不出来时为 nil
    private static func lastTagColor(in tagsData: Data) -> Int? {
        guard
            let tags = try? PropertyListSerialization.propertyList(
                from: tagsData,
                format: nil
            ) as? [String]
        else {
            return nil
        }

        // 每项是 “名称\n颜色号”：颜色号在最后一个换行之后，没有换行就没写颜色号
        return tags
            .compactMap {
                let components = $0.split(separator: "\n", omittingEmptySubsequences: false)

                guard
                    components.count > 1,
                    let color = components.last.flatMap({ Int($0) }),
                    (1 ... 7).contains(color)
                else {
                    return nil
                }

                return color
            }
            .last
    }

    /// Finder flags 里 “有自定义图标” 的位是否置位
    /// - Parameter finderInfo: Finder 信息扩展属性的内容
    private static func isCustomIconFlagSet(in finderInfo: Data) -> Bool {
        guard finderInfo.count >= 10 else { return false }

        // 偏移 8 起的 2 字节，大端
        let bytes = [UInt8](finderInfo)
        let flags = UInt16(bytes[8]) << 8 | UInt16(bytes[9])

        return flags & customIconFlag != 0
    }

    /// 文件夹里是否有存放自定义图标的 `Icon\r`
    /// - Parameter path: 文件夹的路径
    private static func hasCustomIconFile(inFolderAt path: String) -> Bool {
        let iconFilePath = URL(filePath: path, directoryHint: .isDirectory)
            .appending(path: customIconFileName)
            .path(percentEncoded: false)

        var info = stat()

        return lstat(iconFilePath, &info) == 0
    }

    /// 读出文件的一个扩展属性
    /// - Parameters:
    ///   - name: 扩展属性的名字
    ///   - path: 文件的路径
    /// - Returns: 属性不存在、文件已删除、没有权限时为 nil
    private static func extendedAttribute(_ name: String, ofFileAt path: String) -> Data? {
        // 先问长度，再按长度读；两次之间属性变长时第二次读取失败，当作读不到
        let size = getxattr(path, name, nil, 0, 0, 0)

        guard size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        let readSize = getxattr(path, name, &buffer, size, 0, 0)

        guard readSize > 0 else { return nil }

        return Data(buffer.prefix(readSize))
    }
}
