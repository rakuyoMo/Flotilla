import Foundation
import Testing

// MARK: - LocalizationTests

/// 五种语言的界面文字表：进程只选一种语言，缺键时界面显示的是键名而不是英文，
/// 因此五张表的键必须完全一致、没有空值，并且与代码里引用的键一一对应
struct LocalizationTests {
    /// 支持的语言，即 `Sources/Flotilla/Resources` 下的 `.lproj` 目录名
    static let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko"]

    /// App 源码目录：本文件位于 `Tests/FlotillaTests/` 下，所在目录向上两级是仓库根目录
    private static let sourcesURL = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Sources/Flotilla", directoryHint: .isDirectory)

    /// 每张表都能按属性列表解析，且没有空值
    @Test(arguments: languages)
    func parsesTableWithoutEmptyValues(language: String) throws {
        let table = try Self.table(for: language)

        let emptyKeys = table.filter(\.value.isEmpty).keys

        #expect(!table.isEmpty)
        #expect(emptyKeys.isEmpty, "\(language) 有空值：\(emptyKeys.sorted())")
    }

    /// 每张表的键集合都与英文表完全相同
    @Test(arguments: languages)
    func hasSameKeysAsEnglish(language: String) throws {
        let englishKeys = try Set(Self.table(for: "en").keys)
        let keys = try Set(Self.table(for: language).keys)

        let missingKeys = englishKeys.subtracting(keys)
        let extraKeys = keys.subtracting(englishKeys)

        #expect(missingKeys.isEmpty, "\(language) 缺少的键：\(missingKeys.sorted())")
        #expect(extraKeys.isEmpty, "\(language) 多出的键：\(extraKeys.sorted())")
    }

    /// 代码里引用的每个键都在表里，表里的每个键都被代码引用
    @Test
    func matchesKeysReferencedInCode() throws {
        let tableKeys = try Set(Self.table(for: "en").keys)
        let referencedKeys = try Self.keysReferencedInCode()

        let untranslatedKeys = referencedKeys.subtracting(tableKeys)
        let unusedKeys = tableKeys.subtracting(referencedKeys)

        #expect(untranslatedKeys.isEmpty, "代码引用了、表里没有的键：\(untranslatedKeys.sorted())")
        #expect(unusedKeys.isEmpty, "表里有、代码没有引用的键：\(unusedKeys.sorted())")
    }
}

// MARK: - Tables

extension LocalizationTests {
    /// 读取并解析一种语言的 `Localizable.strings`：它是 OpenStep 格式的属性列表，顶层为字典
    static func table(for language: String) throws -> [String: String] {
        let url = sourcesURL.appending(path: "Resources/\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)

        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        )

        return try #require(propertyList as? [String: String])
    }
}

// MARK: - Private

extension LocalizationTests {
    /// 扫描 App 源码里全部 `String(localized: "键"` 形式的调用，取出引用的键；
    /// 调用可能跨行书写，括号与参数标签之间允许空白
    private static func keysReferencedInCode() throws -> Set<String> {
        let enumerator = try #require(FileManager.default.enumerator(
            at: sourcesURL,
            includingPropertiesForKeys: nil
        ))

        let swiftFiles = enumerator
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }

        let pattern = #/String\(\s*localized:\s*"(?<key>[^"]+)"/#

        var keys = Set<String>()

        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)

            for match in source.matches(of: pattern) {
                keys.insert(String(match.key))
            }
        }

        return keys
    }
}
