// 按 website/locales/ 里的语言清单与各语言文案，把 website/pages/ 下的页面模板生成每种语言的页面
// 由 Scripts/site.sh 调用；全部页面先在内存里生成，校验都通过后才写盘，出错时不留下半套页面
// 用法：swift Scripts/generate-site-pages.swift <website 目录> <输出目录>
//
// 模板里的占位符有两类：
// - `{{home.hero.title}}`：文案，取自 locales/<语言代码>.json 里按分组嵌套的同名键，按 HTML 原样插入
// - `{{@lang}}`：`@` 开头，按语言、按页面算出的值或片段，可用的名称见 `computedValues(for:languages:page:)`
// 值有多行时，续行补上占位符所在行的缩进

import Foundation

/// 官网的地址：canonical、og:url、hreflang 与分享图的绝对地址都以它开头
let siteURL = "https://flotilla.rakuyo.dev/"

/// `@` 占位符里按语言、按页面算出的值的名称；`links.名称` 另按语言清单里的链接校验
let computedNames: Set = [
    "lang",
    "root",
    "assets",
    "url",
    "siteURL",
    "alternates",
    "ogLocale",
    "imageLanguage",
    "languageName",
    "languageOptions",
    "headScript",
]

/// 模板里的一个占位符：`range` 是含 `{{` `}}` 的整段，`name` 是两者之间的内容，
/// `line` 是所在的行号，`indent` 是该行的缩进，`inAttribute` 表示它位于标签的属性值里
typealias Placeholder = (
    range: Range<String.Index>,
    name: String,
    line: Int,
    indent: String,
    inAttribute: Bool
)

/// 一个页面模板：`path` 是相对 pages/ 的路径，也是每种语言目录下的输出路径
typealias Template = (path: String, content: String, placeholders: [Placeholder])

// MARK: - Language

/// 语言清单里的一种语言
struct Language {
    /// 语言代码，与 `Sources/Flotilla/Resources/` 下的 `.lproj` 同名：既是文案的文件名，也是 `<html lang>` 与 `hreflang`
    let code: String

    /// 这种语言的页面所在的目录，相对站点根目录，如 `""`、`"zh/"`
    let directory: String

    /// 语言菜单里的名称
    let name: String

    /// `og:locale` 的值，如 `en_US`
    let ogLocale: String

    /// 截图与分享图用哪种语言的一套，即图片文件名里的语言段，如 `en`、`zh`
    let imageLanguage: String

    /// 各语言不同的链接，模板里写作 `{{@links.名称}}`
    let links: [String: String]
}

// 参数依次为 website 目录与输出目录
guard CommandLine.arguments.count == 3 else {
    fail("需要两个参数，用法：swift Scripts/generate-site-pages.swift <website 目录> <输出目录>")
}

generatePages(
    websiteDirectory: CommandLine.arguments[1],
    outputDirectory: CommandLine.arguments[2]
)

// MARK: - Generating

/// 读入语言清单、各语言文案与页面模板，校验通过后生成每种语言的全部页面，写进输出目录
func generatePages(websiteDirectory: String, outputDirectory: String) {
    let localesDirectory = "\(websiteDirectory)/locales"

    // 1. 读入语言清单、每种语言的文案与全部页面模板
    let languages = readLanguages(at: "\(localesDirectory)/languages.json")
    let texts = readTexts(of: languages, in: localesDirectory)
    let templates = readTemplates(in: "\(websiteDirectory)/pages")

    // 2. 校验占位符、文案的键与链接的名称，问题一次列全
    stopIfNeeded(
        checkPlaceholders(in: templates)
            + checkTextKeys(of: languages, texts: texts, templates: templates)
            + checkLinks(of: languages, templates: templates)
    )

    // 3. 在内存里生成全部页面，属性值里不合规的值一并列出
    var pages: [(path: String, content: String)] = []
    var problems: [String] = []

    for language in languages {
        for template in templates {
            let page = render(
                template,
                language: language,
                languages: languages,
                texts: texts[language.code] ?? [:]
            )

            pages.append((language.directory + template.path, page.content))
            problems += page.problems
        }
    }

    stopIfNeeded(problems)

    // 4. 全部生成成功后才写盘
    for page in pages {
        write(page.content, to: "\(outputDirectory)/\(page.path)")
    }
}

/// 用一种语言的文案与算出的值替换模板里的占位符，返回生成的页面，以及属性值里含 `"` 或换行的值
func render(
    _ template: Template,
    language: Language,
    languages: [Language],
    texts: [String: String]
) -> (content: String, problems: [String]) {
    let computed = computedValues(for: language, languages: languages, page: template.path)

    var content = ""
    var problems: [String] = []
    var position = template.content.startIndex

    for placeholder in template.placeholders {
        let name = placeholder.name

        // 占位符与键都已校验过，这里一定取得到值
        let value = name.hasPrefix("@") ? computed[String(name.dropFirst())] : texts[name]

        // 属性值以 `"` 包裹，值里的 `"` 或换行会截断属性，不能原样插入
        if placeholder.inAttribute, let value, value.contains("\"") || value.contains("\n") {
            problems.append(
                "\(language.code) 的 {{\(name)}} 用在 pages/\(template.path) 第 \(placeholder.line) 行的属性值里，不能含 \" 或换行"
            )
        }

        content += template.content[position ..< placeholder.range.lowerBound]
        content += indented(value ?? "", by: placeholder.indent)
        position = placeholder.range.upperBound
    }

    content += template.content[position...]
    return (content, problems)
}

/// 按语言与页面算出 `@` 占位符的值
///
/// - `lang`：语言代码，用于 `<html lang>`
/// - `root`：本页到站点根目录的相对路径，在根目录时为 `./`，用于 `<html data-root>`
/// - `assets`：本页到 `assets/` 目录的相对路径
/// - `url`：本页的绝对地址，用于 canonical 与 `og:url`
/// - `siteURL`：官网的地址
/// - `alternates`：每种语言与 `x-default` 的 `hreflang` 备选链接
/// - `ogLocale`、`imageLanguage`：语言清单里的同名字段
/// - `languageName`：语言菜单里当前语言的名称
/// - `languageOptions`：语言菜单的选项
/// - `headScript`：`<head>` 里先于渲染执行的脚本
/// - `links.名称`：语言清单里这种语言的链接
func computedValues(
    for language: Language,
    languages: [Language],
    page: String
) -> [String: String] {
    // 页面在语言目录下的地址，省略末尾的 `index.html`，如 `releases/`
    let pagePath = page.hasSuffix("index.html")
        ? String(page.dropLast("index.html".count))
        : page

    // 语言目录与页面路径里每有一层目录，回到站点根目录就要多退一层
    let depth = (language.directory + page).count { $0 == "/" }
    let prefix = String(repeating: "../", count: depth)

    var values = [
        "lang": language.code,
        "root": prefix.isEmpty ? "./" : prefix,
        "assets": prefix + "assets/",
        "url": siteURL + language.directory + pagePath,
        "siteURL": siteURL,
        "alternates": alternateLinks(languages: languages, pagePath: pagePath),
        "ogLocale": language.ogLocale,
        "imageLanguage": language.imageLanguage,
        "languageName": language.name,

        "languageOptions": languageOptions(
            languages: languages,
            current: language,
            prefix: prefix,
            pagePath: pagePath
        ),

        "headScript": headScript(
            languages: languages,
            prefix: prefix,
            pagePath: pagePath
        ),
    ]

    for (name, url) in language.links {
        values["links.\(name)"] = url
    }

    return values
}

// MARK: - Fragments

/// 每种语言与 `x-default` 的 `hreflang` 备选链接，`x-default` 指向默认语言，即语言清单的第一项
func alternateLinks(languages: [Language], pagePath: String) -> String {
    let entries = languages.map { ($0.code, $0.directory) }
        + [("x-default", languages[0].directory)]

    return entries
        .map { hreflang, directory in
            """
            <link
              rel="alternate"
              hreflang="\(hreflang)"
              href="\(siteURL + directory + pagePath)"
            >
            """
        }
        .joined(separator: "\n\n")
}

/// 语言菜单的选项，按语言清单的顺序排列，每个选项链到这种语言的同一页面
func languageOptions(
    languages: [Language],
    current: Language,
    prefix: String,
    pagePath: String
) -> String {
    languages
        .map {
            languageOption(
                $0,
                href: relativePath(prefix: prefix, language: $0, pagePath: pagePath),
                isCurrent: $0.code == current.code
            )
        }
        .joined(separator: "\n\n")
}

/// 语言菜单里的一个选项；当前语言多一个 `aria-current` 属性与名称后的对勾
func languageOption(_ language: Language, href: String, isCurrent: Bool) -> String {
    let opening = """
        <li>
          <a
            href="\(href)"
            hreflang="\(language.code)"
            lang="\(language.code)"
            data-language-switch="\(language.code)"
        """

    let currentAttribute = """
            aria-current="true"
        """

    let name = """
          >
            \(language.name)
        """

    let check = """
            <svg
              class="icon"
              aria-hidden="true"
            ><use href="#i-check"/></svg>
        """

    let closing = """
          </a>
        </li>
        """

    let parts = isCurrent
        ? [opening, currentAttribute, name, check, closing]
        : [opening, name, closing]

    return parts.joined(separator: "\n")
}

/// `<head>` 里先于渲染执行的脚本：标记脚本可用，再算出目标语言，与本页语言不同就跳到目标语言的同一页面，保留锚点
///
/// 目标语言依次取：
/// - 在语言菜单里选过的语言：site.js 写进 `localStorage` 的 `flotilla.language`，键名与 site.js 的 `LANGUAGE_KEY` 一致
/// - 浏览器的首选语言：只看列表的第一项，补全文字后按 “语言 + 文字” 与语言清单逐项比对
/// - 默认语言，即语言清单的第一项
///
/// 首选语言不往列表后面找：繁体环境下 Chrome 的列表常是 `zh-TW, zh, en-US, en`，往后找会被 `zh` 带到简体中文页
func headScript(languages: [Language], prefix: String, pagePath: String) -> String {
    // 每种语言的代码与本页在这种语言下的相对地址，按语言清单的顺序写成脚本里的数组
    let pages = languages
        .map { language in
            let href = relativePath(prefix: prefix, language: language, pagePath: pagePath)
            return "{ code: \"\(language.code)\", href: \"\(href)\" },"
        }
        .joined(separator: "\n")

    return """
        <!-- 按选过的语言或浏览器的首选语言跳到对应语言的同一页面；先于渲染执行，避免先闪一下本页 -->
        <script>
          (() => {
            document.documentElement.classList.add("js");

            // 每种语言的代码与本页在这种语言下的地址，第一项是默认语言
            const pages = [
              \(indented(pages, by: "      "))
            ];

            // 在语言菜单里选过的语言；值不在清单里或读取失败时，当作没选过
            const saved = (() => {
              try {
                const code = localStorage.getItem("flotilla.language");
                return pages.find((page) => page.code === code);
              } catch {
                return undefined;
              }
            })();

            // 浏览器的首选语言：只看第一项，补全文字后按 “语言 + 文字” 比对；
            // 标签无效或浏览器不支持 Intl.Locale 时，当作没有匹配
            const preferred = (() => {
              try {
                const tag = navigator.languages?.[0] ?? navigator.language;
                const locale = new Intl.Locale(tag).maximize();

                return pages.find((page) => {
                  const candidate = new Intl.Locale(page.code).maximize();

                  return candidate.language === locale.language
                    && candidate.script === locale.script;
                });
              } catch {
                return undefined;
              }
            })();

            const target = saved ?? preferred ?? pages[0];

            if (target.code !== document.documentElement.lang) {
              location.replace(target.href + location.hash);
            }
          })();
        </script>
        """
}

/// 从本页到某种语言的同一页面的相对地址；目标就是站点根目录时写作 `./`
func relativePath(prefix: String, language: Language, pagePath: String) -> String {
    let path = prefix + language.directory + pagePath
    return path.isEmpty ? "./" : path
}

// MARK: - Checking

/// 校验每个占位符的写法：`@` 开头的须是已知的名称，其余须是由字母、数字与点组成的文案键；`{{` `}}` 须成对
func checkPlaceholders(in templates: [Template]) -> [String] {
    var problems: [String] = []

    for template in templates {
        for placeholder in template.placeholders where !isKnownPlaceholder(placeholder.name) {
            problems.append("pages/\(template.path) 第 \(placeholder.line) 行：未知的占位符 {{\(placeholder.name)}}")
        }

        // 去掉全部占位符后仍有 `{{` 或 `}}` 的行，是写坏了的占位符
        var remainder = template.content

        for placeholder in template.placeholders.reversed() {
            remainder.replaceSubrange(placeholder.range, with: "")
        }

        let brokenLines = remainder
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .filter { $0.element.contains("{{") || $0.element.contains("}}") }

        for line in brokenLines {
            problems.append("pages/\(template.path) 第 \(line.offset + 1) 行：未知的占位符，`{{` 与 `}}` 不成对")
        }
    }

    return problems
}

/// 校验每种语言的文案与模板用到的文案键一一对应：缺的、多的都列出语言与键
func checkTextKeys(
    of languages: [Language],
    texts: [String: [String: String]],
    templates: [Template]
) -> [String] {
    let used = Set(
        templates
            .flatMap(\.placeholders)
            .map(\.name)
            .filter(isTextKey)
    )

    return languages.flatMap { language in
        let file = "locales/\(language.code).json"
        let provided = Set(texts[language.code]?.keys.map(\.self) ?? [])

        return describe(used.subtracting(provided), as: "\(file) 缺少模板用到的键")
            + describe(provided.subtracting(used), as: "\(file) 里有模板没用到的键")
    }
}

/// 校验每种语言的链接与模板用到的 `{{@links.名称}}` 一一对应：缺的、多的都列出语言与名称
func checkLinks(of languages: [Language], templates: [Template]) -> [String] {
    let used = Set(
        templates
            .flatMap(\.placeholders)
            .map(\.name)
            .filter { $0.hasPrefix("@links.") && isKnownPlaceholder($0) }
            .map { String($0.dropFirst("@links.".count)) }
    )

    return languages.flatMap { language in
        let field = "语言清单里 \(language.code) 的 links"
        let provided = Set(language.links.keys)

        return describe(used.subtracting(provided), as: "\(field) 缺少模板用到的链接")
            + describe(provided.subtracting(used), as: "\(field) 里有模板没用到的链接")
    }
}

/// 占位符的名称是否可用：`@` 开头的须是已知的名称或 `links.名称`，其余须是文案键
func isKnownPlaceholder(_ name: String) -> Bool {
    guard name.hasPrefix("@") else {
        return isTextKey(name)
    }

    let computedName = String(name.dropFirst())

    guard computedName.hasPrefix("links.") else {
        return computedNames.contains(computedName)
    }

    return isTextKey(String(computedName.dropFirst("links.".count)))
}

/// 是否是文案键的写法：由点分隔的若干段，每段以字母开头，只含字母与数字
func isTextKey(_ name: String) -> Bool {
    name
        .split(separator: ".", omittingEmptySubsequences: false)
        .allSatisfy { segment in
            (segment.first?.isLetter ?? false)
                && segment.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
}

/// 把一组有问题的键写成一条报错，键按字母顺序逐行列出；没有键时不报
func describe(_ keys: Set<String>, as title: String) -> [String] {
    guard !keys.isEmpty else {
        return []
    }

    let lines = keys
        .sorted()
        .map { "      \($0)" }

    return [title + "：\n" + lines.joined(separator: "\n")]
}

// MARK: - Reading

/// 读取语言清单：非空的数组，每项的字段齐全，语言代码与目录各不相同
func readLanguages(at path: String) -> [Language] {
    guard let items = readJSON(at: path) as? [[String: Any]], !items.isEmpty else {
        fail("\(path) 须是非空的数组，每项是一种语言")
    }

    let languages = items
        .enumerated()
        .map { language(from: $0.element, number: $0.offset + 1, path: path) }

    // 语言代码决定文案文件，目录决定输出位置，重复了会互相覆盖
    let codes = languages.map(\.code)
    let directories = languages.map(\.directory)

    guard Set(codes).count == codes.count, Set(directories).count == directories.count else {
        fail("\(path) 里的语言代码与目录都不能重复")
    }

    return languages
}

/// 把语言清单里的一项转成 `Language`，字段缺失或类型不对时报错退出
func language(from item: [String: Any], number: Int, path: String) -> Language {
    // 逐个取出字符串字段，缺哪个报哪个
    func string(_ key: String) -> String {
        guard let value = item[key] as? String else {
            fail("\(path) 第 \(number) 项缺少字符串字段 \(key)")
        }

        return value
    }

    guard let links = item["links"] as? [String: String] else {
        fail("\(path) 第 \(number) 项缺少 links，或其中有不是字符串的链接")
    }

    // 空字符串表示站点根目录；其余是相对路径，以 `/` 结尾
    let directory = string("directory")

    guard directory.isEmpty || (directory.hasSuffix("/") && !directory.hasPrefix("/")) else {
        fail("\(path) 第 \(number) 项的 directory 须为空字符串，或是以 / 结尾的相对路径")
    }

    return Language(
        code: string("code"),
        directory: directory,
        name: string("name"),
        ogLocale: string("ogLocale"),
        imageLanguage: string("imageLanguage"),
        links: links
    )
}

/// 读取语言清单里每种语言的文案，展平成 “点分隔的键 → 文案”；文案文件须与语言清单一一对应
func readTexts(of languages: [Language], in directory: String) -> [String: [String: String]] {
    // 不在语言清单里的文案文件说明两边没有同步，与缺文件一样报错
    let listed = Set(languages.map { "\($0.code).json" } + ["languages.json"])
    let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []

    var problems = files
        .filter { $0.hasSuffix(".json") && !listed.contains($0) }
        .sorted()
        .map { "locales/\($0) 不在语言清单里" }

    var texts: [String: [String: String]] = [:]

    for language in languages {
        let path = "\(directory)/\(language.code).json"

        guard FileManager.default.fileExists(atPath: path) else {
            problems.append("语言清单里有 \(language.code)，却没有 locales/\(language.code).json")
            continue
        }

        guard let object = readJSON(at: path) as? [String: Any] else {
            problems.append("locales/\(language.code).json 须是一个对象")
            continue
        }

        var flattened: [String: String] = [:]
        problems += flatten(object, prefix: "", into: &flattened, file: "locales/\(language.code).json")
        texts[language.code] = flattened
    }

    stopIfNeeded(problems)
    return texts
}

/// 把嵌套的文案展平成 “点分隔的键 → 文案”；字符串数组是多行文案，按行拼接；返回值类型不对的键
func flatten(
    _ object: [String: Any],
    prefix: String,
    into result: inout [String: String],
    file: String
) -> [String] {
    var problems: [String] = []

    for (name, value) in object {
        let key = prefix.isEmpty ? name : "\(prefix).\(name)"

        switch value {
        case let group as [String: Any]:
            problems += flatten(group, prefix: key, into: &result, file: file)

        case let text as String:
            result[key] = text

        case let lines as [String]:
            result[key] = lines.joined(separator: "\n")

        default:
            problems.append("\(file) 里 \(key) 的值须是字符串或字符串数组")
        }
    }

    return problems
}

/// 读取模板目录下的全部 `.html` 页面模板，按路径排序，并找出其中的占位符
func readTemplates(in directory: String) -> [Template] {
    guard let enumerator = FileManager.default.enumerator(atPath: directory) else {
        fail("读取 \(directory) 失败")
    }

    let paths = enumerator
        .compactMap { $0 as? String }
        .filter { $0.hasSuffix(".html") }
        .sorted()

    guard !paths.isEmpty else {
        fail("\(directory) 下没有页面模板")
    }

    return paths.map { path in
        let content = readText(at: "\(directory)/\(path)")
        return (path, content, placeholders(in: content))
    }
}

/// 找出模板里的全部占位符：`{{` 与同一行里随后的第一个 `}}` 之间的内容，其中不含花括号
func placeholders(in content: String) -> [Placeholder] {
    var result: [Placeholder] = []
    var line = 1
    var counted = content.startIndex
    var searchStart = content.startIndex

    while
        let open = content.range(of: "{{", range: searchStart ..< content.endIndex),
        let close = content.range(of: "}}", range: open.upperBound ..< content.endIndex)
    {
        searchStart = close.upperBound
        let name = String(content[open.upperBound ..< close.lowerBound])

        // 跨行或含花括号的不算占位符，留给 `checkPlaceholders(in:)` 报不成对
        guard !name.contains(where: { "\n{}".contains($0) }) else {
            searchStart = open.upperBound
            continue
        }

        // 行号从上一个占位符往后接着数，不必每次从头数
        line += content[counted ..< open.lowerBound].utf8.count { $0 == UInt8(ascii: "\n") }
        counted = open.lowerBound

        let lineStart = content[..<open.lowerBound]
            .lastIndex(of: "\n")
            .map(content.index(after:))
            ?? content.startIndex

        result.append((
            range: open.lowerBound ..< close.upperBound,
            name: name,
            line: line,
            indent: String(content[lineStart...].prefix { $0 == " " || $0 == "\t" }),
            inAttribute: isInAttribute(content, at: open.lowerBound)
        ))
    }

    return result
}

/// 某个位置是否在标签的属性值里：往前最近的尖括号是 `<`，且两者之间的 `"` 为奇数个
func isInAttribute(_ content: String, at index: String.Index) -> Bool {
    let preceding = content[..<index]

    guard
        let bracket = preceding.lastIndex(where: { $0 == "<" || $0 == ">" }),
        preceding[bracket] == "<"
    else {
        return false
    }

    return preceding[bracket...].count { $0 == "\"" } % 2 == 1
}

// MARK: - Helpers

/// 多行的值插入模板时，续行补上占位符所在行的缩进；空行保持为空
func indented(_ value: String, by indent: String) -> String {
    value
        .split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
        .map { index, line in
            index == 0 || line.isEmpty ? String(line) : indent + line
        }
        .joined(separator: "\n")
}

/// 读取并解析一个 JSON 文件，读不到或不是合法的 JSON 时报错退出
func readJSON(at path: String) -> Any {
    do {
        return try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)))
    } catch {
        fail("读取 \(path) 失败：\(error.localizedDescription)")
    }
}

/// 以 UTF-8 读取一个文本文件，读不到时报错退出
func readText(at path: String) -> String {
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        fail("读取 \(path) 失败：\(error.localizedDescription)")
    }
}

/// 把页面写到指定路径，所在目录不存在时先创建
func write(_ content: String, to path: String) {
    let url = URL(fileURLWithPath: path)

    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try Data(content.utf8).write(to: url, options: .atomic)
    } catch {
        fail("写入 \(path) 失败：\(error.localizedDescription)")
    }
}

/// 有问题时逐条输出到标准错误，并以非零状态退出
func stopIfNeeded(_ problems: [String]) {
    guard !problems.isEmpty else {
        return
    }

    let lines = problems.map { "  - \($0)" }
    fail("生成官网页面失败：\n" + lines.joined(separator: "\n"))
}

/// 向标准错误输出中文报错，并以非零状态退出
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("错误：\(message)\n".utf8))
    exit(1)
}
