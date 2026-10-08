import Foundation
import Testing

// MARK: - LocalizedAppNameTests

/// App 名的本地化：访达、Dock、App 菜单等处，简繁中文环境下显示中文名“归帆”“歸帆”，日文环境下显示日文名“帰帆”，其它语言显示“Flotilla”
struct LocalizedAppNameTests {
    /// 每种语言下的 App 名：简繁中文用中文名，日文用日文名，其它语言沿用英文名
    static let appNames = [
        "en": "Flotilla",
        "zh-Hans": "归帆",
        "zh-Hant": "歸帆",
        "ja": "帰帆",
        "ko": "Flotilla",
    ]

    /// `InfoPlist.strings` 里给出 App 名的键：访达与 Dock 取显示名，App 菜单取短名
    static let nameKeys: Set<String> = [
        "CFBundleDisplayName",
        "CFBundleName",
    ]

    /// Info.plist 打开 App 名的本地化，且基准显示名与包的文件名相同：
    /// 访达先比较基准显示名与包的文件名，相同才显示 `InfoPlist.strings` 里的译名，否则显示文件名；
    /// 打包脚本按可执行文件名给包命名
    @Test
    func infoPlistEnablesLocalizedName() throws {
        let infoPlist = try PrivacyUsageDescriptionTests.infoPlist()

        let executableName = try #require(infoPlist["CFBundleExecutable"] as? String)
        let hasLocalizedName = try #require(infoPlist["LSHasLocalizedDisplayName"] as? Bool)

        #expect(infoPlist["CFBundleDisplayName"] as? String == executableName)
        #expect(hasLocalizedName)
    }

    /// 每种语言的 `InfoPlist.strings` 都给出这种语言下的 App 名，显示名与短名相同
    @Test(arguments: LocalizationTests.languages)
    func localizesAppName(language: String) throws {
        let appName = try #require(Self.appNames[language], "\(language) 没有定下 App 名")
        let table = try LocalizationTests.table("InfoPlist", for: language)

        for key in Self.nameKeys.sorted() {
            #expect(table[key] == appName, "\(language) 的 \(key)")
        }
    }
}
