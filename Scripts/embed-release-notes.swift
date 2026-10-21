// 把这一版每种语言的更新说明嵌进 Sparkle 更新清单，并按语言给出 “版本历史记录” 打开的官网更新日志页
// 由 Scripts/appcast.sh 在 generate_appcast 之后调用；改写会让清单原有的签名失效，之后须用 sign_update 重签
// 用法：swift Scripts/embed-release-notes.swift <appcast.xml> <说明目录>

import Foundation

/// Sparkle 的 XML 命名空间，`sparkle:` 前缀的元素属于它
let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

/// 每种语言的代码与官网更新日志页，按写进清单的顺序排列
///
/// 语言代码与 `Sources/Flotilla/Resources/` 下的 `.lproj` 同名，既是说明的文件名，也是元素的 `xml:lang`：
/// Sparkle 在同名元素里按用户的语言偏好挑出一个
///
/// Scripts/check-release-notes.sh 里有同一组语言，两边同步修改
let languages: [(code: String, releasesPage: String)] = [
    ("en", "https://flotilla.rakuyo.dev/releases/"),
    ("zh-Hans", "https://flotilla.rakuyo.dev/zh/releases/"),
    ("zh-Hant", "https://flotilla.rakuyo.dev/zh-hant/releases/"),
    ("ja", "https://flotilla.rakuyo.dev/ja/releases/"),
    ("ko", "https://flotilla.rakuyo.dev/ko/releases/"),
    ("de", "https://flotilla.rakuyo.dev/de/releases/"),
    ("fr", "https://flotilla.rakuyo.dev/fr/releases/"),
    ("es", "https://flotilla.rakuyo.dev/es/releases/"),
]

// 参数依次为清单路径与说明目录
guard CommandLine.arguments.count == 3 else {
    fail("需要两个参数，用法：swift Scripts/embed-release-notes.swift <appcast.xml> <说明目录>")
}

embedReleaseNotes(
    appcastPath: CommandLine.arguments[1],
    notesDirectory: CommandLine.arguments[2]
)

// MARK: - Embedding

/// 把说明目录里每种语言的说明与更新日志页链接加进清单唯一的条目，校验后写回原文件
func embedReleaseNotes(appcastPath: String, notesDirectory: String) {
    let appcastURL = URL(fileURLWithPath: appcastPath)

    // 1. 先读入全部说明，缺一份就在改动清单之前退出
    let notes = languages.map { readNotes(at: "\(notesDirectory)/\($0.code).md") }

    // 2. 读入 generate_appcast 生成的清单，取出其中唯一的条目
    let document: XMLDocument

    do {
        document = try XMLDocument(contentsOf: appcastURL, options: .nodeLoadExternalEntitiesNever)
    } catch {
        fail("读取 \(appcastPath) 失败：\(error.localizedDescription)")
    }

    guard
        let items = try? document.nodes(forXPath: "/rss/channel/item"),
        items.count == 1,
        let item = items.first as? XMLElement
    else {
        fail("\(appcastPath) 须恰好包含一个 <item>")
    }

    // 3. 先加每种语言的说明，再加每种语言的更新日志页链接；同类元素按语言顺序相邻，`en` 在前
    for (language, content) in zip(languages, notes) {
        item.addChild(descriptionElement(language: language.code, content: content))
    }

    for language in languages {
        item.addChild(releasesPageElement(language: language.code, url: language.releasesPage))
    }

    // 4. 按缩进格式序列化，确认解析结果与读入的说明一致后再落盘
    let data = document.xmlData(options: .nodePrettyPrint)

    verifyDescriptions(in: data, expected: notes)

    do {
        try data.write(to: appcastURL, options: .atomic)
    } catch {
        fail("写入 \(appcastPath) 失败：\(error.localizedDescription)")
    }
}

// MARK: - Helpers

/// 读取一份说明，换行统一为 LF
///
/// XML 1.0 规定解析时把 CRLF 与单独的 CR 统一成 LF，NSXMLDocument 却不统一 CDATA 里的换行；
/// 先统一成 LF，清单里的说明不随解析器是否照做而变，写盘前的校验也按统一后的文本比对
func readNotes(at path: String) -> String {
    let content: String

    do {
        content = try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        fail("读取 \(path) 失败：\(error.localizedDescription)")
    }

    // 先换 CRLF，再换剩下的单独 CR，CRLF 不会变成两个换行
    return content
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
}

/// 某种语言的内嵌说明：`<description xml:lang="…" sparkle:format="markdown">`，说明文本放在 CDATA 里
func descriptionElement(language: String, content: String) -> XMLElement {
    let element = XMLElement(name: "description")

    element.addAttribute(attribute(name: "xml:lang", value: language))
    element.addAttribute(attribute(name: "sparkle:format", value: "markdown"))

    element.setChildren(cdataNodes(for: content))
    return element
}

/// 某种语言的 `<sparkle:fullReleaseNotesLink>`：“已是最新版本” 提示框里的 “版本历史记录” 按钮打开它
func releasesPageElement(language: String, url: String) -> XMLElement {
    let element = XMLElement(name: "sparkle:fullReleaseNotesLink", uri: sparkleNamespace)

    element.addAttribute(attribute(name: "xml:lang", value: language))

    element.stringValue = url
    return element
}

/// 按 Sparkle 读清单的方式解析序列化结果，确认每种语言恰好一份说明，且与读入的说明逐字节相同
func verifyDescriptions(in data: Data, expected notes: [String]) {
    guard
        let parsed = try? XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever),
        let descriptions = try? parsed.nodes(forXPath: "/rss/channel/item/description") as? [XMLElement]
    else {
        fail("无法解析改写后的清单")
    }

    for (language, content) in zip(languages, notes) {
        let matches = descriptions.filter {
            $0.attribute(forName: "xml:lang")?.stringValue == language.code
        }

        guard matches.count == 1, matches.first?.stringValue == content else {
            fail("改写后的清单里，\(language.code) 的说明与读入的文本不一致")
        }
    }
}

/// 把文本拆成一组 CDATA 节点，依次拼接即为原来的文本
///
/// CDATA 段里不能出现 `]]>`：文本里每出现一次，就从 `]]` 与 `>` 之间断开，分进前后两段
func cdataNodes(for content: String) -> [XMLNode] {
    var segments = content.components(separatedBy: "]]>")

    // 每个断开处，前一段补回 `]]`，后一段补回 `>`
    for index in segments.indices.dropLast() {
        segments[index] += "]]"
        segments[index + 1] = ">" + segments[index + 1]
    }

    return segments.map {
        let node = XMLNode(kind: .text, options: .nodeIsCDATA)
        node.stringValue = $0
        return node
    }
}

/// 按名称原样创建的属性节点，`xml:lang`、`sparkle:format` 这类带前缀的名称照原样写进清单
func attribute(name: String, value: String) -> XMLNode {
    let attribute = XMLNode(kind: .attribute)
    attribute.name = name
    attribute.stringValue = value
    return attribute
}

/// 向标准错误输出中文报错，并以非零状态退出
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("错误：\(message)\n".utf8))
    exit(1)
}
