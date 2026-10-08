import Foundation
import Testing

// MARK: - PrivacyUsageDescriptionTests

/// 隐私授权框里的用途说明：第一次读取“文稿”“桌面”等受保护位置时系统弹出授权框，
/// 每个会弹授权框的位置都要在 Info.plist 里写明 Flotilla 为什么要访问，五种语言都要有译文
struct PrivacyUsageDescriptionTests {
    /// 会弹授权框的位置对应的用途说明键：桌面、文稿、下载、iCloud 云盘（文件提供方）、网络卷、外接卷
    private static let usageDescriptionKeys: Set<String> = [
        "NSDesktopFolderUsageDescription",
        "NSDocumentsFolderUsageDescription",
        "NSDownloadsFolderUsageDescription",
        "NSFileProviderDomainUsageDescription",
        "NSNetworkVolumesUsageDescription",
        "NSRemovableVolumesUsageDescription",
    ]

    /// Info.plist 为每个会弹授权框的位置都写了说明，且不是空串
    @Test
    func infoPlistDescribesEveryProtectedLocation() throws {
        let infoPlist = try Self.infoPlist()

        let undescribedKeys = Self.usageDescriptionKeys.filter {
            (infoPlist[$0] as? String)?.isEmpty ?? true
        }

        #expect(undescribedKeys.isEmpty, "Info.plist 缺少或为空的说明：\(undescribedKeys.sorted())")
    }

    /// 每种语言的 `InfoPlist.strings` 都能解析、没有空值，覆盖 Info.plist 里的全部用途说明键；
    /// 除用途说明外只有 App 名的键，拼错的键会作为多出的键报出来
    @Test(arguments: LocalizationTests.languages)
    func localizesEveryUsageDescription(language: String) throws {
        let table = try LocalizationTests.table("InfoPlist", for: language)

        // Info.plist 里所有以 `UsageDescription` 结尾的键都是用途说明，译文表要一个不差地覆盖
        let infoPlistKeys = try Set(
            Self.infoPlist().keys.filter { $0.hasSuffix("UsageDescription") }
        )

        let keys = Set(table.keys)

        let missingKeys = infoPlistKeys.subtracting(keys)
        let emptyKeys = table.filter(\.value.isEmpty).keys

        let extraKeys = keys
            .subtracting(infoPlistKeys)
            .subtracting(LocalizedAppNameTests.nameKeys)

        #expect(missingKeys.isEmpty, "\(language) 缺少的键：\(missingKeys.sorted())")
        #expect(extraKeys.isEmpty, "\(language) 多出的键：\(extraKeys.sorted())")
        #expect(emptyKeys.isEmpty, "\(language) 有空值：\(emptyKeys.sorted())")
    }
}

// MARK: - Info.plist

extension PrivacyUsageDescriptionTests {
    /// 读取并解析 App 的 `Info.plist`：XML 格式的属性列表，顶层为字典
    static func infoPlist() throws -> [String: Any] {
        let url = LocalizationTests.sourcesURL.appending(path: "Info.plist")
        let data = try Data(contentsOf: url)

        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        )

        return try #require(propertyList as? [String: Any])
    }
}
