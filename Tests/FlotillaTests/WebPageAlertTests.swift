import AppKit
import Testing

@testable import Flotilla

// MARK: - WebPageAlertTests

/// 网页的提示框：输入的文字要像浏览器地址栏那样成为网页，不是网址的输入在确认之前就挡下，
/// 用户点了 “添加” 就一定加得进去；标题留空时自动获取，但用户自己输入的标题永远优先；
/// 编辑时改的是原来那一项，原来的标题同样算用户输入的
@MainActor
struct WebPageAlertTests {
    /// 假的取标题与停顿，并记下提示框交出的网页与补上的标题
    private let stub = WebPageAlertStub()

    /// 本用例添加网页的提示框，取标题与等停顿都由 `stub` 代替
    private let addWebPageAlert: WebPageAlert

    /// 用假环境建好提示框
    init() {
        addWebPageAlert = stub.makeAlert()
    }

    // MARK: 输入怎样成为网页

    /// 完整的网址原样采用，不改大小写、末尾斜杠与 `www.`；输入的网页没有标题，显示名就是网址
    @Test(arguments: [
        "https://www.apple.com/cn/",
        "http://example.com/path?q=1",
        "HTTPS://EXAMPLE.COM",
    ])
    func completeAddressIsKeptAsTyped(address: String) {
        let item = WebPageAlert.webPage(from: address)

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
        let item = WebPageAlert.webPage(from: input)

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
        let item = WebPageAlert.webPage(from: input)

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
        #expect(WebPageAlert.webPage(from: input) == nil)
    }

    /// 文件 URL 不可用，指向的目录确实存在也不成为文件项：这里只加网页，文件走 “添加文件…”
    @Test
    func fileURLIsRejectedEvenIfDirectoryExists() {
        #expect(FileManager.default.fileExists(atPath: "/Applications"))
        #expect(WebPageAlert.webPage(from: "file:///Applications") == nil)
    }

    // MARK: 提示框

    /// 刚弹出时输入为空，“添加” 禁用；网址随时变成可用或不可用，“添加” 跟着变，标题框的内容不影响它
    @Test
    func addButtonFollowsAddressOnly() throws {
        let fields = try textFields(of: addWebPageAlert)
        let addButton = try #require(addWebPageAlert.alert.buttons.first)

        // 提示框自己是两个输入框的 delegate
        #expect(fields.address.delegate === addWebPageAlert)
        #expect(fields.title.delegate === addWebPageAlert)

        #expect(!addButton.isEnabled)

        let expectations = [
            ("apple.com", true),
            ("ftp://x", false),
        ]

        for (input, isEnabled) in expectations {
            type(input, into: fields.address)

            #expect(addButton.isEnabled == isEnabled, "输入 \(input) 时 “添加” 的可用状态不对")
        }

        type("Apple", into: fields.title)

        #expect(!addButton.isEnabled)
    }

    /// “添加” 是默认按钮，回车触发；“取消” 按 Esc 触发：只有英文标题 “Cancel” 会自动得到 Esc
    @Test
    func returnAddsAndEscapeCancels() {
        #expect(addWebPageAlert.alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"])
    }

    /// 标题、说明、按钮与两个输入框的占位文字都用界面文字表里的键；测试进程读不到译文，读到的是键名
    @Test
    func textsComeFromLocalizationKeys() throws {
        let alert = addWebPageAlert.alert
        let fields = try textFields(of: addWebPageAlert)

        #expect(alert.messageText == "folders.webPageAlert.message")
        #expect(alert.informativeText == "folders.webPageAlert.informative")

        #expect(alert.buttons.map(\.title) == [
            "folders.webPageAlert.add",
            "folders.webPageAlert.cancel",
        ])

        #expect(fields.address.placeholderString == "folders.webPageAlert.addressPlaceholder")
        #expect(fields.title.placeholderString == "folders.webPageAlert.titlePlaceholder")
    }

    /// 网址框在上、标题框在下，都与上方的说明文字左右对齐，不把提示框撑宽；网址框是窗口的第一响应者
    @Test
    func textFieldsAreStackedAndAlignedWithText() throws {
        let alert = addWebPageAlert.alert
        let fields = try textFields(of: addWebPageAlert)

        #expect(alert.window.initialFirstResponder === fields.address)

        alert.layout()

        let contentView = try #require(alert.window.contentView)
        let informativeField = try #require(
            labels(in: contentView).first { $0.stringValue == alert.informativeText }
        )

        let addressFrame = fields.address.convert(fields.address.bounds, to: contentView)
        let titleFrame = fields.title.convert(fields.title.bounds, to: contentView)
        let textFrame = informativeField.convert(informativeField.bounds, to: contentView)

        #expect(addressFrame.minY > titleFrame.maxY)

        for fieldFrame in [addressFrame, titleFrame] {
            #expect(fieldFrame.minX == textFrame.minX)
            #expect(fieldFrame.maxX == textFrame.maxX)
        }
    }

    /// 弹出后不点输入框就能打字：网址框已是第一响应者；Tab 到标题框，Shift-Tab 回到网址框
    @Test
    func tabMovesBetweenAddressAndTitle() throws {
        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        let alertWindow = addWebPageAlert.alert.window
        let fields = try textFields(of: addWebPageAlert)

        stub.beginSheet(of: addWebPageAlert, on: window)

        #expect(editedField(in: alertWindow) === fields.address)

        alertWindow.selectNextKeyView(nil)

        #expect(editedField(in: alertWindow) === fields.title)

        alertWindow.selectPreviousKeyView(nil)

        #expect(editedField(in: alertWindow) === fields.address)

        window.endSheet(alertWindow)
    }
}

// MARK: - Title Fetching

extension WebPageAlertTests {
    /// 网址可用并停顿下来才开始获取，取的是补好 scheme 的网址：不可用的输入与停顿之前都不联网，
    /// 停顿之内网址又变了就重新计时，只为最后的网址获取一次
    @Test
    func fetchStartsAfterPauseWithCompletedAddress() throws {
        let fields = try textFields(of: addWebPageAlert)

        type("hello world", into: fields.address)
        stub.endPauses()

        #expect(stub.requestedURLs.isEmpty)

        type("apple.c", into: fields.address)
        type("apple.co", into: fields.address)
        type("apple.com", into: fields.address)

        #expect(stub.requestedURLs.isEmpty)

        stub.endPauses()

        #expect(stub.requestedURLs == [try url("https://apple.com")])
    }

    /// 获取期间网址变了：前一次被取消，停顿之后为新网址重新获取
    @Test
    func changingAddressCancelsFetch() throws {
        let fields = try textFields(of: addWebPageAlert)

        type("apple.com", into: fields.address)
        stub.endPauses()

        type("apple.com/cn", into: fields.address)

        #expect(stub.cancelledURLs == [try url("https://apple.com")])

        stub.endPauses()

        #expect(stub.requestedURLs == [
            try url("https://apple.com"),
            try url("https://apple.com/cn"),
        ])
    }

    /// 取到时标题框空着就填进去，首尾的空白去掉
    @Test(arguments: [
        ("Apple", "Apple"),
        ("  Apple (中国大陆)\n", "Apple (中国大陆)"),
    ])
    func fetchedTitleFillsEmptyTitleField(fetched: String, expected: String) throws {
        let fields = try textFields(of: addWebPageAlert)

        type("apple.com", into: fields.address)
        stub.endPauses()
        stub.complete(try url("https://apple.com"), with: fetched)

        #expect(fields.title.stringValue == expected)
    }

    /// 取不到、或者取到的只有空白：标题框保持空着，不提示错误
    @Test(arguments: [nil, "", " \n "] as [String?])
    func missingTitleLeavesTitleFieldEmpty(fetched: String?) throws {
        let fields = try textFields(of: addWebPageAlert)

        type("apple.com", into: fields.address)
        stub.endPauses()
        stub.complete(try url("https://apple.com"), with: fetched)

        #expect(fields.title.stringValue.isEmpty)
        #expect(try !isShowingFetchingTitle())
    }

    /// 用户在获取期间自己输入的标题，取到的结果不覆盖
    @Test
    func userTitleIsNeverOverwritten() throws {
        let fields = try textFields(of: addWebPageAlert)

        type("apple.com", into: fields.address)
        stub.endPauses()

        type("我的标题", into: fields.title)
        stub.complete(try url("https://apple.com"), with: "Apple")

        #expect(fields.title.stringValue == "我的标题")
    }

    /// 换了网址：自动填进去的旧标题清空，换成新网址的标题；被取消的那一次晚到的结果丢掉
    @Test
    func autofilledTitleFollowsAddress() throws {
        let fields = try textFields(of: addWebPageAlert)
        let apple = try url("https://apple.com")
        let python = try url("https://python.org")

        type("apple.com", into: fields.address)
        stub.endPauses()
        stub.complete(apple, with: "Apple")

        #expect(fields.title.stringValue == "Apple")

        type("python.org", into: fields.address)

        #expect(fields.title.stringValue.isEmpty)

        // 换网址之前又开始了一次 apple.com 的获取，换网址时被取消，它的结果晚于新的请求到达
        type("apple.com", into: fields.address)
        stub.endPauses()

        type("python.org", into: fields.address)
        stub.endPauses()

        stub.complete(apple, with: "Apple")

        #expect(fields.title.stringValue.isEmpty)

        stub.complete(python, with: "Welcome to Python.org")

        #expect(fields.title.stringValue == "Welcome to Python.org")
    }

    /// 换了网址，用户自己输入的标题保留，新网址的结果也不覆盖它
    @Test
    func userTitleSurvivesAddressChange() throws {
        let fields = try textFields(of: addWebPageAlert)

        type("apple.com", into: fields.address)
        type("我的标题", into: fields.title)

        type("python.org", into: fields.address)
        stub.endPauses()
        stub.complete(try url("https://python.org"), with: "Welcome to Python.org")

        #expect(fields.title.stringValue == "我的标题")
    }

    /// 获取期间标题框照样可以输入；转圈与 “正在获取标题…” 只在获取中、标题框空着时显示，取完恢复
    @Test
    func progressShowsOnlyWhileFetchingIntoEmptyTitle() throws {
        let fields = try textFields(of: addWebPageAlert)

        #expect(try !isShowingFetchingTitle())

        // 还在等停顿，没有开始获取
        type("apple.com", into: fields.address)

        #expect(try !isShowingFetchingTitle())

        stub.endPauses()

        #expect(try isShowingFetchingTitle())
        #expect(fields.title.isEditable)
        #expect(fields.title.isEnabled)

        type("我", into: fields.title)

        #expect(try !isShowingFetchingTitle())

        type("", into: fields.title)

        #expect(try isShowingFetchingTitle())

        stub.complete(try url("https://apple.com"), with: nil)

        #expect(try !isShowingFetchingTitle())
    }
}

// MARK: - Adding and Cancelling

extension WebPageAlertTests {
    /// 标题框有内容：带着去掉首尾空白的标题加入；正在进行的获取被取消，之后取到的标题不再补
    @Test
    func addWithTitleUsesItAndCancelsFetch() throws {
        let fields = try textFields(of: addWebPageAlert)
        let apple = try url("https://apple.com")

        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        stub.beginSheet(of: addWebPageAlert, on: window)

        type("apple.com", into: fields.address)
        stub.endPauses()

        type("  我的标题 ", into: fields.title)
        try clickFirstButton(of: addWebPageAlert)

        #expect(try onlyConfirmedWebPage().url == apple)
        #expect(try onlyConfirmedWebPage().title == "我的标题")
        #expect(stub.cancelledURLs == [apple])

        stub.complete(apple, with: "Apple")

        #expect(stub.filledTitles.isEmpty)
    }

    /// 标题框空着、正在获取：先不带标题加入，显示名是网址；取到后补到这一项上，只获取一次。
    /// 标题连同加入的那一份网页交出：补之前要核对的网址，就是加入时的网址
    @Test
    func addWithoutTitleFillsTitleLater() throws {
        let fields = try textFields(of: addWebPageAlert)
        let apple = try url("https://apple.com")

        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        stub.beginSheet(of: addWebPageAlert, on: window)

        type("apple.com", into: fields.address)
        stub.endPauses()

        try clickFirstButton(of: addWebPageAlert)

        let webPage = try onlyConfirmedWebPage()

        #expect(webPage.title == nil)
        #expect(stub.filledTitles.isEmpty)
        #expect(stub.cancelledURLs.isEmpty)

        stub.complete(apple, with: " Apple ")

        #expect(stub.filledTitles.map(\.title) == ["Apple"])
        #expect(stub.filledTitles.map(\.webPage) == [webPage])
        #expect(stub.filledTitles.map(\.webPage.url) == [apple])
        #expect(stub.requestedURLs == [apple])
    }

    /// 标题框空着、还在等停顿：立刻开始获取，不再等；停顿结束时也不重复获取
    @Test
    func addBeforePauseFetchesImmediately() throws {
        let fields = try textFields(of: addWebPageAlert)
        let apple = try url("https://apple.com")

        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        stub.beginSheet(of: addWebPageAlert, on: window)

        type("apple.com", into: fields.address)
        try clickFirstButton(of: addWebPageAlert)

        #expect(stub.requestedURLs == [apple])

        stub.endPauses()

        #expect(stub.requestedURLs == [apple])

        stub.complete(apple, with: "Apple")

        #expect(stub.filledTitles.map(\.title) == ["Apple"])
        #expect(stub.filledTitles.map(\.webPage) == [try onlyConfirmedWebPage()])
    }

    /// 标题框空着、取不到标题：网页照样加入，什么都不补
    @Test
    func addWithoutTitleKeepsAddressWhenTitleIsMissing() throws {
        let fields = try textFields(of: addWebPageAlert)
        let apple = try url("https://apple.com")

        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        stub.beginSheet(of: addWebPageAlert, on: window)

        type("apple.com", into: fields.address)
        stub.endPauses()

        try clickFirstButton(of: addWebPageAlert)

        stub.complete(apple, with: nil)

        #expect(try onlyConfirmedWebPage().displayName == "https://apple.com")
        #expect(stub.filledTitles.isEmpty)
    }

    /// “取消” 与 Esc：正在进行的获取被取消，正在等的停顿作废，什么都不加入，之后取到的标题也不补
    @Test
    func cancelAddsNothing() throws {
        let fields = try textFields(of: addWebPageAlert)
        let apple = try url("https://apple.com")

        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        stub.beginSheet(of: addWebPageAlert, on: window)

        type("apple.com", into: fields.address)
        stub.endPauses()

        // 新网址还在等停顿时点 “取消”
        type("apple.com/cn", into: fields.address)

        let cancelButton = try #require(addWebPageAlert.alert.buttons.last)
        cancelButton.performClick(nil)

        stub.endPauses()
        stub.complete(apple, with: "Apple")

        #expect(stub.confirmedWebPages.isEmpty)
        #expect(stub.requestedURLs == [apple])
        #expect(stub.filledTitles.isEmpty)
    }
}

// MARK: - Time Limit

extension WebPageAlertTests {
    /// 获取进行中到时：这一次被取消，转圈消失、占位文字恢复，当作取不到；
    /// 转圈不会一直转下去，之后才到的标题也不再突然填进标题框
    @Test
    func timeLimitCancelsFetchAndDropsLateTitle() throws {
        let fields = try textFields(of: addWebPageAlert)
        let apple = try url("https://apple.com")

        type("apple.com", into: fields.address)
        stub.endPauses()

        #expect(try isShowingFetchingTitle())

        stub.endTimeLimit(of: apple)

        #expect(stub.cancelledURLs == [apple])
        #expect(try !isShowingFetchingTitle())

        stub.complete(apple, with: "Apple")

        #expect(fields.title.stringValue.isEmpty)
    }

    /// 不带标题加入之后到时：时限从开始获取时算起，点 “添加” 不重新计时；
    /// 这一次被取消，这一项保持显示网址，之后才到的标题不补
    @Test
    func timeLimitAfterAddingKeepsAddress() throws {
        let fields = try textFields(of: addWebPageAlert)
        let apple = try url("https://apple.com")

        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        stub.beginSheet(of: addWebPageAlert, on: window)

        type("apple.com", into: fields.address)
        stub.endPauses()

        try clickFirstButton(of: addWebPageAlert)

        stub.endTimeLimit(of: apple)

        #expect(stub.cancelledURLs == [apple])

        stub.complete(apple, with: "Apple")

        #expect(try onlyConfirmedWebPage().displayName == "https://apple.com")
        #expect(stub.filledTitles.isEmpty)
    }

    /// 换了网址之后，旧网址那一次的时限到了：新网址的获取不受影响，不被取消、转圈还在，取到的标题照样填入
    @Test
    func earlierTimeLimitLeavesNewFetchAlone() throws {
        let fields = try textFields(of: addWebPageAlert)
        let apple = try url("https://apple.com")
        let python = try url("https://python.org")

        type("apple.com", into: fields.address)
        stub.endPauses()

        type("python.org", into: fields.address)
        stub.endPauses()

        stub.endTimeLimit(of: apple)

        // 取消只有换网址时的那一次
        #expect(stub.cancelledURLs == [apple])
        #expect(try isShowingFetchingTitle())

        stub.complete(python, with: "Welcome to Python.org")

        #expect(fields.title.stringValue == "Welcome to Python.org")
    }

    /// 已经取完之后到时：什么都不发生，不再取消，填好的标题保留
    @Test
    func timeLimitAfterTitleArrivesDoesNothing() throws {
        let fields = try textFields(of: addWebPageAlert)
        let apple = try url("https://apple.com")

        type("apple.com", into: fields.address)
        stub.endPauses()
        stub.complete(apple, with: "Apple")

        stub.endTimeLimit(of: apple)

        #expect(stub.cancelledURLs.isEmpty)
        #expect(fields.title.stringValue == "Apple")
    }
}

// MARK: - Editing

extension WebPageAlertTests {
    /// 编辑：两个框填着这个网页的网址与标题；标题与第一个按钮换成编辑的文字，说明文字与添加相同；
    /// 网址可用，“保存” 一弹出就可用，随输入实时更新，规则与 “添加” 相同
    @Test
    func editFillsFieldsAndUsesEditTexts() throws {
        let editAlert = stub.makeAlert(editing: try exampleWebPage(title: "Example Domain"))
        let fields = try textFields(of: editAlert)
        let alert = editAlert.alert

        #expect(fields.address.stringValue == "https://example.com/")
        #expect(fields.title.stringValue == "Example Domain")

        #expect(alert.messageText == "folders.webPageAlert.editMessage")
        #expect(alert.informativeText == addWebPageAlert.alert.informativeText)

        #expect(alert.buttons.map(\.title) == [
            "folders.webPageAlert.save",
            "folders.webPageAlert.cancel",
        ])

        #expect(alert.buttons.map(\.keyEquivalent) == ["\r", "\u{1b}"])

        let saveButton = try #require(alert.buttons.first)

        #expect(saveButton.isEnabled)

        type("hello world", into: fields.address)

        #expect(!saveButton.isEnabled)

        type("apple.com", into: fields.address)

        #expect(saveButton.isEnabled)
    }

    /// 没有标题的网页：标题框空着，显示的是 “标题（可选）”；网址没改过就保存，不获取标题，交出的网页与原来的相同
    @Test
    func editUntitledWebPageWithoutChangesFetchesNothing() throws {
        let original = try exampleWebPage(title: nil)
        let editAlert = stub.makeAlert(editing: original)
        let fields = try textFields(of: editAlert)

        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        #expect(fields.title.stringValue.isEmpty)
        #expect(fields.title.placeholderString == "folders.webPageAlert.titlePlaceholder")

        stub.beginSheet(of: editAlert, on: window)
        stub.endPauses()

        try clickFirstButton(of: editAlert)

        #expect(try onlyConfirmedWebPage() == original)
        #expect(stub.requestedURLs.isEmpty)
        #expect(stub.filledTitles.isEmpty)
    }

    /// 保存后交出的网页沿用原来的 id，改过的网址与标题按 “添加” 的规则规整：补上 `https://`，标题去掉首尾空白
    @Test
    func editKeepsIDAndNormalizesInput() throws {
        let original = try exampleWebPage(title: "Example Domain")
        let editAlert = stub.makeAlert(editing: original)
        let fields = try textFields(of: editAlert)

        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        stub.beginSheet(of: editAlert, on: window)

        type("apple.com", into: fields.address)
        type("  Apple ", into: fields.title)

        try clickFirstButton(of: editAlert)

        let expected = WebPageReference(
            id: original.id,
            url: try url("https://apple.com"),
            title: "Apple"
        )

        #expect(try onlyConfirmedWebPage() == expected)
    }

    /// 弹出时不获取，网址改了、停顿之后才获取；原来的标题算用户的内容：换网址时不清空，取到的标题也不覆盖
    @Test
    func editFetchesOnlyAfterAddressChangesAndKeepsOriginalTitle() throws {
        let editAlert = stub.makeAlert(editing: try exampleWebPage(title: "Example Domain"))
        let fields = try textFields(of: editAlert)
        let apple = try url("https://apple.com")

        stub.endPauses()

        #expect(stub.requestedURLs.isEmpty)

        type("apple.com", into: fields.address)

        #expect(fields.title.stringValue == "Example Domain")

        stub.endPauses()

        #expect(stub.requestedURLs == [apple])

        stub.complete(apple, with: "Apple")

        #expect(fields.title.stringValue == "Example Domain")
    }

    /// 清空标题、改了网址后保存：先不带标题交出，id 是原来的；
    /// 取到后连同保存的那一份交出，是原来的 id 与新的网址，补之前按新网址核对
    @Test
    func editWithClearedTitleFillsTitleLaterWithOriginalID() throws {
        let original = try exampleWebPage(title: "Example Domain")
        let editAlert = stub.makeAlert(editing: original)
        let fields = try textFields(of: editAlert)
        let apple = try url("https://apple.com")

        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        stub.beginSheet(of: editAlert, on: window)

        type("", into: fields.title)
        type("apple.com", into: fields.address)
        stub.endPauses()

        try clickFirstButton(of: editAlert)

        let saved = try onlyConfirmedWebPage()

        #expect(saved.id == original.id)
        #expect(saved.url == apple)
        #expect(saved.title == nil)

        stub.complete(apple, with: " Apple ")

        #expect(stub.filledTitles.map(\.title) == ["Apple"])
        #expect(stub.filledTitles.map(\.webPage) == [saved])
    }

    /// 不带标题加入之后、获取还没完时又把网址改掉，同样不带标题保存：两次获取补的是同一项。
    /// 旧网址的标题先到时不补到新网址上，也不挡住新网址随后取到的标题
    @Test
    func lateTitleOfOldAddressIsDroppedAfterEditing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "FlotillaTests-\(UUID().uuidString)")

        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FolderStore(fileURL: directory.appending(path: "folders.json"))
        let folder = store.addRootFolder(named: "根")
        let apple = try url("https://apple.com")
        let python = try url("https://python.org")

        let window = makeSheetParentWindow()
        defer { window.orderOut(nil) }

        // 添加 apple.com、标题留空：先不带标题加入，获取还没完
        let addFields = try textFields(of: addWebPageAlert)

        addWebPageAlert.beginSheetModal(
            for: window,
            completionHandler: {
                store.addItems([.webPage($0)], to: folder.id)
            },
            titleHandler: {
                store.fillTitle($0, of: $1)
            }
        )

        type("apple.com", into: addFields.address)
        try clickFirstButton(of: addWebPageAlert)

        let added = try #require(firstWebPage(in: store))

        // 编辑这一项：网址改成 python.org、标题留空保存，这次获取同样还没完
        let editAlert = stub.makeAlert(editing: added)
        let editFields = try textFields(of: editAlert)

        editAlert.beginSheetModal(
            for: window,
            completionHandler: {
                store.updateWebPage($0)
            },
            titleHandler: {
                store.fillTitle($0, of: $1)
            }
        )

        type("python.org", into: editFields.address)
        try clickFirstButton(of: editAlert)

        let saved = WebPageReference(id: added.id, url: python, title: nil)

        #expect(stub.requestedURLs == [apple, python])
        #expect(firstWebPage(in: store) == saved)

        // apple.com 的标题先到：这一项的网址已是 python.org，不补
        stub.complete(apple, with: "Apple")

        #expect(firstWebPage(in: store) == saved)

        // python.org 的标题随后到：补上
        stub.complete(python, with: "Python")

        let titled = WebPageReference(id: added.id, url: python, title: "Python")

        #expect(firstWebPage(in: store) == titled)
    }
}

// MARK: - Private

extension WebPageAlertTests {
    /// 提示框里的网址框与标题框：网址框在上
    private func textFields(of webPageAlert: WebPageAlert) throws -> (address: NSTextField, title: NSTextField) {
        let accessoryView = try #require(webPageAlert.alert.accessoryView)

        let fields = accessoryView.subviews
            .compactMap { $0 as? NSTextField }
            .sorted { $0.frame.minY > $1.frame.minY }

        try #require(fields.count == 2)

        return (fields[0], fields[1])
    }

    /// 标题框内右端的转圈
    private func progressIndicator() throws -> NSProgressIndicator {
        try #require(
            addWebPageAlert.alert.accessoryView?.subviews
                .compactMap { $0 as? NSProgressIndicator }
                .first
        )
    }

    /// 标题框此刻是否显示 “正在获取”：转圈与 “正在获取标题…” 总是一起出现、一起换回 “标题（可选）”
    private func isShowingFetchingTitle() throws -> Bool {
        let fields = try textFields(of: addWebPageAlert)
        let isSpinning = try !progressIndicator().isHidden

        let expectedPlaceholder = isSpinning
            ? "folders.webPageAlert.fetchingTitle"
            : "folders.webPageAlert.titlePlaceholder"

        #expect(fields.title.placeholderString == expectedPlaceholder, "转圈与占位文字没有一起换")

        return isSpinning
    }

    /// 像用户键入那样改掉输入框的文字：改值，再按 delegate 的方式通知，不需要屏幕
    /// - Parameters:
    ///   - text: 输入框改成的文字
    ///   - field: 网址框或标题框
    private func type(_ text: String, into field: NSTextField) {
        field.stringValue = text

        field.delegate?.controlTextDidChange?(
            Notification(name: NSControl.textDidChangeNotification, object: field)
        )
    }

    /// 点提示框的第一个按钮：添加时是 “添加”，编辑时是 “保存”；它禁用时点不动，与屏上一样
    private func clickFirstButton(of webPageAlert: WebPageAlert) throws {
        try #require(webPageAlert.alert.buttons.first).performClick(nil)
    }

    /// 要编辑的网页：`https://example.com/`，id 随机
    /// - Parameter title: 网页的标题；没有时传 nil
    private func exampleWebPage(title: String?) throws -> WebPageReference {
        WebPageReference(id: UUID(), url: try url("https://example.com/"), title: title)
    }

    /// 数据源里第一个根文件夹的第一项：是网页时给出它，否则为 nil
    private func firstWebPage(in store: FolderStore) -> WebPageReference? {
        guard case .webPage(let webPage) = store.rootFolders.first?.items.first else { return nil }

        return webPage
    }

    /// 提示框交出的唯一一个网页
    private func onlyConfirmedWebPage() throws -> WebPageReference {
        try #require(
            stub.confirmedWebPages.count == 1,
            "应当只交出一个网页：\(stub.confirmedWebPages)"
        )

        return stub.confirmedWebPages[0]
    }

    /// 窗口正在编辑的输入框：第一响应者是字段编辑器，它的 delegate 就是那个输入框
    private func editedField(in window: NSWindow) -> NSTextField? {
        (window.firstResponder as? NSTextView)?.delegate as? NSTextField
    }

    /// 网址
    private func url(_ address: String) throws -> URL {
        try #require(URL(string: address))
    }

    /// 挂 sheet 的窗口：弹出 sheet 时它会被放上屏幕，放在所有屏幕之外
    private func makeSheetParentWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    /// 视图里的全部只读文字，包括子视图的子视图
    private func labels(in view: NSView) -> [NSTextField] {
        let directLabels = view.subviews
            .compactMap { $0 as? NSTextField }
            .filter { !$0.isEditable }

        return directLabels + view.subviews.flatMap { labels(in: $0) }
    }
}
