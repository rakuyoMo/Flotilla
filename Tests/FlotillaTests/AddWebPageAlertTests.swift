import AppKit
import Testing

@testable import Flotilla

// MARK: - AddWebPageAlertTests

/// “添加网页…” 的提示框：输入的文字要像浏览器地址栏那样成为网页，不是网址的输入在确认之前就挡下，
/// 用户点了 “添加” 就一定加得进去
@MainActor
struct AddWebPageAlertTests {
    // MARK: 输入怎样成为网页

    /// 完整的网址原样采用，不改大小写、末尾斜杠与 `www.`；输入的网页没有标题，显示名就是网址
    @Test(arguments: [
        "https://www.apple.com/cn/",
        "http://example.com/path?q=1",
        "HTTPS://EXAMPLE.COM",
    ])
    func completeAddressIsKeptAsTyped(address: String) {
        let item = AddWebPageAlert.webPage(from: address)

        guard case .webPage(let webPage) = item else {
            Issue.record("\(address) 应当是网页：\(String(describing: item))")
            return
        }

        #expect(webPage.url.absoluteString == address)
        #expect(webPage.title == nil)
        #expect(webPage.displayName == address)
    }

    /// 首尾的空白与换行被去掉：从别处拷来的网址常带着它们
    @Test(arguments: [
        "  https://www.apple.com/cn/  ",
        "\nhttps://www.apple.com/cn/\n",
        "\t https://www.apple.com/cn/ \r\n",
    ])
    func surroundingWhitespaceIsTrimmed(input: String) {
        let item = AddWebPageAlert.webPage(from: input)

        guard case .webPage(let webPage) = item else {
            Issue.record("\(input.debugDescription) 应当是网页：\(String(describing: item))")
            return
        }

        #expect(webPage.url.absoluteString == "https://www.apple.com/cn/")
    }

    /// 没写 scheme 时像浏览器地址栏那样补上 `https://`，其余保持输入的样子；
    /// 只看开头：查询参数里带着另一个网址时同样要补，否则整段被判为不可用
    @Test(arguments: [
        ("apple.com", "https://apple.com"),
        ("apple.com/path?q=1", "https://apple.com/path?q=1"),
        ("localhost:8080", "https://localhost:8080"),
        ("apple.com/?u=https://x.com", "https://apple.com/?u=https://x.com"),
        ("localhost:8080/?next=http://x", "https://localhost:8080/?next=http://x"),
    ])
    func missingSchemeBecomesHTTPS(input: String, expected: String) {
        let item = AddWebPageAlert.webPage(from: input)

        guard case .webPage(let webPage) = item else {
            Issue.record("\(input) 应当是网页：\(String(describing: item))")
            return
        }

        #expect(webPage.url.absoluteString == expected)
    }

    /// 空输入、一句话、没有主机名的网址与 `http`、`https` 以外的网址都不可用
    @Test(arguments: [
        "",
        " \n\t ",
        "hello world",
        "https://",
        "ftp://example.com",
    ])
    func unusableInputIsRejected(input: String) {
        #expect(AddWebPageAlert.webPage(from: input) == nil)
    }

    /// 文件 URL 不可用，指向的目录确实存在也不成为文件项：这里只加网页，文件走 “添加文件…”
    @Test
    func fileURLIsRejectedEvenIfDirectoryExists() {
        #expect(FileManager.default.fileExists(atPath: "/Applications"))
        #expect(AddWebPageAlert.webPage(from: "file:///Applications") == nil)
    }

    // MARK: 提示框

    /// 刚弹出时输入为空，“添加” 禁用；输入随时变成可用或不可用的网址，“添加” 跟着变
    @Test
    func addButtonFollowsInput() throws {
        let addWebPageAlert = AddWebPageAlert()
        let alert = addWebPageAlert.alert

        let textField = try #require(alert.accessoryView as? NSTextField)
        let addButton = try #require(alert.buttons.first)

        // 提示框自己是输入框的 delegate；delegate 是弱引用，这里取出的强引用让它在测试期间一直活着
        let delegate = try #require(textField.delegate)

        #expect(delegate === addWebPageAlert)
        #expect(!addButton.isEnabled)

        // 不需要屏幕：直接改输入框的值，再按 delegate 的方式通知
        let expectations = [
            ("apple.com", true),
            ("ftp://x", false),
        ]

        for (input, isEnabled) in expectations {
            textField.stringValue = input

            delegate.controlTextDidChange?(
                Notification(name: NSControl.textDidChangeNotification, object: textField)
            )

            #expect(addButton.isEnabled == isEnabled, "输入 \(input) 时 “添加” 的可用状态不对")
        }
    }

    /// “添加” 是默认按钮，回车触发；“取消” 按 Esc 触发：只有英文标题 “Cancel” 会自动得到 Esc
    @Test
    func returnAddsAndEscapeCancels() {
        let alert = AddWebPageAlert().alert

        #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"])
    }

    /// 标题、说明与按钮都用界面文字表里的键；测试进程读不到译文，读到的是键名
    @Test
    func textsComeFromLocalizationKeys() {
        let alert = AddWebPageAlert().alert

        #expect(alert.messageText == "folders.webPageAlert.message")
        #expect(alert.informativeText == "folders.webPageAlert.informative")

        #expect(alert.buttons.map(\.title) == [
            "folders.webPageAlert.add",
            "folders.webPageAlert.cancel",
        ])
    }

    /// 弹出时输入框就是第一响应者，可以直接打字；输入框与上方的说明文字左右对齐，不把提示框撑宽
    @Test
    func textFieldIsFocusedAndAlignedWithText() throws {
        let alert = AddWebPageAlert().alert
        let textField = try #require(alert.accessoryView as? NSTextField)

        #expect(alert.window.initialFirstResponder === textField)

        alert.layout()

        let contentView = try #require(alert.window.contentView)
        let informativeField = try #require(
            labels(in: contentView).first { $0.stringValue == alert.informativeText }
        )

        let fieldFrame = textField.convert(textField.bounds, to: contentView)
        let textFrame = informativeField.convert(informativeField.bounds, to: contentView)

        #expect(fieldFrame.minX == textFrame.minX)
        #expect(fieldFrame.maxX == textFrame.maxX)
    }
}

// MARK: - Private

extension AddWebPageAlertTests {
    /// 视图里的全部只读文字，包括子视图的子视图
    private func labels(in view: NSView) -> [NSTextField] {
        let directLabels = view.subviews
            .compactMap { $0 as? NSTextField }
            .filter { !$0.isEditable }

        return directLabels + view.subviews.flatMap { labels(in: $0) }
    }
}
