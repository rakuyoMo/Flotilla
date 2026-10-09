import AppKit

// MARK: - WebPageAlert

/// 网页的提示框，“添加网页…” 与网页的 “编辑…” 共用：输入网址与可选的标题，
/// 点 “添加” 后得到要加入组的网页，点 “保存” 后得到改好的网页
///
/// 输入不是可用的网址时 “添加” “保存” 禁用，随输入实时更新：确认之后不会再报错，也不必再弹第二个提示框。
/// 网址改了、停顿一会儿不再变时自动获取网页的标题，填进空着的标题框；获取期间标题框照样可以输入，用户输入的内容不被覆盖
@MainActor
final class WebPageAlert: NSObject {
    /// 提示框正文距左右两边的距离，实测（macOS 27）；输入框按它与正文左右对齐
    private static let textInset: CGFloat = 20

    /// 网址框与标题框上下之间的距离
    private static let fieldSpacing: CGFloat = 8

    /// 网址停顿多久不再变，才开始获取标题
    private static let pauseDuration = Duration.milliseconds(300)

    /// 一次获取最多等多久：从开始获取算起，不含停顿；到时还没有结果就取消，当作取不到
    private static let timeLimit = Duration.seconds(10)

    /// 提示框：标题、说明、“添加” 或 “保存” 与 “取消” 两个按钮，网址框与标题框作为附件
    let alert = NSAlert()

    /// 正在编辑的网页；添加时为 nil
    private let editedWebPage: WebPageReference?

    /// 输入网址的单行输入框，弹出时是第一响应者
    private let addressField = NSTextField(string: "")

    /// 输入标题的单行输入框；留空时自动获取网页的标题
    private let titleField = NSTextField(string: "")

    /// 正在获取标题、标题框又空着时，显示在标题框内右端的转圈
    private let progressIndicator = NSProgressIndicator()

    /// 开始取一个网址的标题，在主线程把结果交给回调；返回取消这一次的闭包
    private let fetchTitle: (URL, @escaping @MainActor (String?) -> Void) -> () -> Void

    /// 等网址停顿一会儿，然后在主线程执行给它的闭包
    private let waitForPause: (@escaping @MainActor () -> Void) -> Void

    /// 等一次获取的时限到，然后在主线程执行给它的闭包
    private let waitForTimeLimit: (@escaping @MainActor () -> Void) -> Void

    /// 正在等的那次停顿：编号，与停顿结束后要取标题的网址；网址再变、开始获取或关掉提示框时清空
    private var pendingPause: (id: UUID, url: URL)?

    /// 正在进行的那一次获取：编号，与取消它的闭包；没有在获取时为 nil
    private var titleFetch: (id: UUID, cancel: () -> Void)?

    /// 上一次自动填进标题框的标题；标题框里的文字仍与它相同，就是用户没改过
    private var autofilledTitle: String?

    /// 网页已不带标题交出之后，把取到的标题补到那一项上；还没交出时为 nil
    private var fillConfirmedWebPageTitle: ((String) -> Void)?

    /// 用 LinkPresentation 获取标题：网址停顿 0.3 s 不再变才开始，一次最多等 10 s
    /// - Parameter webPage: 要编辑的网页；添加时传 nil
    convenience init(editing webPage: WebPageReference? = nil) {
        self.init(
            editing: webPage,
            fetchTitle: WebPageTitleFetcher.fetchTitle(of:completionHandler:),
            waitForPause: Self.waiting(for: Self.pauseDuration),
            waitForTimeLimit: Self.waiting(for: Self.timeLimit)
        )
    }

    /// 配好提示框的文字、按钮与输入框
    ///
    /// 添加时输入为空，“添加” 禁用；编辑时两个框填着这个网页的网址与标题，“保存” 的可用状态按填进去的网址判断
    /// - Parameters:
    ///   - webPage: 要编辑的网页；添加时传 nil
    ///   - fetchTitle: 开始取一个网址的标题，在主线程把结果交给回调，取不到时为 nil；返回取消这一次的闭包。测试里传入假实现
    ///   - waitForPause: 等网址停顿一会儿，然后在主线程执行给它的闭包。测试里传入假实现
    ///   - waitForTimeLimit: 等一次获取的时限到，然后在主线程执行给它的闭包；每开始一次获取就等一次。测试里传入假实现
    init(
        editing webPage: WebPageReference? = nil,
        fetchTitle: @escaping (URL, @escaping @MainActor (String?) -> Void) -> () -> Void,
        waitForPause: @escaping (@escaping @MainActor () -> Void) -> Void,
        waitForTimeLimit: @escaping (@escaping @MainActor () -> Void) -> Void
    ) {
        editedWebPage = webPage
        self.fetchTitle = fetchTitle
        self.waitForPause = waitForPause
        self.waitForTimeLimit = waitForTimeLimit

        super.init()

        alert.messageText = webPage == nil
            ? String(
                localized: "groups.webPageAlert.message",
                comment: "“添加网页…” 提示框的标题"
            )
            : String(
                localized: "groups.webPageAlert.editMessage",
                comment: "网页 “编辑…” 提示框的标题"
            )

        alert.informativeText = String(
            localized: "groups.webPageAlert.informative",
            comment: "网页提示框的说明文字，添加与编辑共用，位于网址框与标题框上方"
        )

        configureButtons()
        configureTextFields()

        // 编辑时填上这个网页的网址与标题；填进去的原标题算用户的内容：换网址时不清空，取到的标题也不覆盖它
        if let webPage {
            addressField.stringValue = webPage.url.absoluteString
            titleField.stringValue = webPage.title ?? ""
        }

        // 第一个按钮起初的可用状态按网址框里的网址判断：添加时网址框空着，“添加” 禁用
        alert.buttons.first?.isEnabled = enteredURL != nil

        updateTitleProgress()
    }

    /// 把输入的网址与标题变成网页，没写 scheme 时像浏览器地址栏那样补上 `https://`；不是可用的网址时为 nil
    ///
    /// 除此之外保持输入的样子：大小写、末尾斜杠、`www.` 都不改
    /// - Parameters:
    ///   - input: 网址框里的文字
    ///   - title: 标题框里的文字；首尾空白会被去掉，空串视为没有标题
    static func webPage(from input: String, title: String? = nil) -> GroupItem? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // 中间还有空白时多半是把一句话当成了网址
        guard
            !text.isEmpty,
            !text.contains(where: \.isWhitespace)
        else {
            return nil
        }

        // 只看开头有没有 `scheme://`（scheme 按 RFC 3986）：查询参数里的 `://` 不算。
        // 不补 scheme 时，`localhost:8080` 会被解析成 scheme 为 `localhost` 的网址
        let hasScheme = text.prefixMatch(of: /[A-Za-z][A-Za-z0-9+.\-]*:\/\//) != nil
        let address = hasScheme ? text : "https://" + text

        // 文件 URL 不交给分类，免得它去读文件系统、把存在的目录当成文件加入；
        // 没有主机名的也不算网页，例如只输入了 `https://`
        guard
            let url = URL(string: address),
            !url.isFileURL,
            let host = url.host(),
            !host.isEmpty
        else {
            return nil
        }

        // 只收 `http`、`https` 由分类决定，与从浏览器拖入的网页同一套规则
        return GroupItem(url: url, title: title)
    }

    /// 以 sheet 挂在窗口上弹出，网址框是第一响应者
    ///
    /// 点 “添加” 或 “保存” 时把输入的网页交给 completionHandler：编辑时沿用原来的 id；标题框有内容时带着这个标题；
    /// 标题框空着时先不带标题交出，提示框关掉之后取到了标题，再连同交出的那一份网页交给 titleHandler 补上。
    /// 点 “取消” 或按 Esc 时什么都不交出
    /// - Parameters:
    ///   - window: 提示框挂在这个窗口上
    ///   - completionHandler: 收到要加入的网页，或改好的网页
    ///   - titleHandler: 不带标题交出的网页取到了标题：收到这个标题，与交出的那一份网页（id 与取标题的网址）。
    ///     交出之后那一项的网址可能又被改掉，补之前要核对网址
    func beginSheetModal(
        for window: NSWindow,
        completionHandler: @escaping @MainActor (WebPageReference) -> Void,
        titleHandler: @escaping @MainActor (_ title: String, _ webPage: WebPageReference) -> Void
    ) {
        // 弹出期间由完成回调持有自己：输入框的 delegate 是弱引用
        alert.beginSheetModal(for: window) { [self] response in
            // 取消：正在进行的获取也不再需要
            guard response == .alertFirstButtonReturn else {
                stopFetchingTitle()
                return
            }

            confirm(completionHandler: completionHandler, titleHandler: titleHandler)
        }

        // 弹出后可以直接打字或粘贴网址，不必先点网址框。
        // 不能只靠 `initialFirstResponder`：macOS 26 上（CI 实测），`beginSheetModal` 返回时第一响应者不是网址框
        alert.window.makeFirstResponder(addressField)
    }
}

// MARK: NSTextFieldDelegate

extension WebPageAlert: NSTextFieldDelegate {
    /// 输入变化时更新，键入与粘贴都会走到这里：
    /// 网址变了就更新 “添加” “保存” 的可用状态、重新获取标题；标题框是否空着决定转圈显示与否
    func controlTextDidChange(_ notification: Notification) {
        if (notification.object as? NSTextField) === addressField {
            addressDidChange()
        }

        updateTitleProgress()
    }
}

// MARK: - Private

extension WebPageAlert {
    /// 网址框里的文字对应的网址；不是可用的网址时为 nil
    private var enteredURL: URL? {
        guard case .webPage(let webPage) = Self.webPage(from: addressField.stringValue) else {
            return nil
        }

        return webPage.url
    }

    /// 加上 “添加”（编辑时是 “保存”）与 “取消”：提示框把第一个按钮设为默认按钮，回车触发它；
    /// 只有英文标题 “Cancel” 会自动得到 Esc，其它语言的 “取消” 要显式设上
    private func configureButtons() {
        alert.addButton(
            withTitle: editedWebPage == nil
                ? String(
                    localized: "groups.webPageAlert.add",
                    comment: "“添加网页…” 提示框的按钮：把输入的网页加入组"
                )
                : String(
                    localized: "groups.webPageAlert.save",
                    comment: "网页 “编辑…” 提示框的按钮：保存改好的网址与标题"
                )
        )

        let cancelButton = alert.addButton(
            withTitle: String(
                localized: "groups.webPageAlert.cancel",
                comment: "网页提示框的按钮，添加与编辑共用：关闭提示框，什么都不变"
            )
        )

        cancelButton.keyEquivalent = "\u{1b}"
    }

    /// 把网址框与标题框上下放在说明文字下方，与正文左右对齐；网址框设为窗口的 `initialFirstResponder`
    ///
    /// 正文宽度随提示框的宽度变化，提示框又随按钮标题变宽：
    /// 先按没有附件的样子排一次，得到提示框的宽度，再扣掉正文两侧的距离
    private func configureTextFields() {
        addressField.delegate = self
        titleField.delegate = self

        addressField.placeholderString = String(
            localized: "groups.webPageAlert.addressPlaceholder",
            comment: "网页提示框里网址框的占位文字，添加与编辑共用"
        )

        alert.layout()

        let width = alert.window.contentLayoutRect.width - 2 * Self.textInset
        let fieldHeight = addressField.intrinsicContentSize.height

        // 附件的坐标原点在左下角：网址框在上，标题框在下。
        // 提示框的窗口按位置排出 Tab 的顺序：Tab 从网址框到标题框，Shift-Tab 回来
        addressField.frame = NSRect(
            x: 0,
            y: fieldHeight + Self.fieldSpacing,
            width: width,
            height: fieldHeight
        )

        titleField.frame = NSRect(x: 0, y: 0, width: width, height: fieldHeight)

        configureProgressIndicator(fieldWidth: width, fieldHeight: fieldHeight)

        // 转圈最后加入，盖在标题框上面
        let accessoryView = NSView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: width,
                height: 2 * fieldHeight + Self.fieldSpacing
            )
        )

        accessoryView.addSubview(addressField)
        accessoryView.addSubview(titleField)
        accessoryView.addSubview(progressIndicator)

        alert.accessoryView = accessoryView

        // `layout()` 已把 `initialFirstResponder` 设成按钮：改成网址框，系统按它设第一响应者时也落在网址框上
        alert.window.initialFirstResponder = addressField
    }

    /// 小号转圈放在标题框内的右端、上下居中；不显示时不占标题框的位置
    /// - Parameters:
    ///   - fieldWidth: 标题框的宽度
    ///   - fieldHeight: 标题框的高度
    private func configureProgressIndicator(fieldWidth: CGFloat, fieldHeight: CGFloat) {
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.sizeToFit()

        // 与标题框右边的距离取上下的留白，四周看起来一样宽
        let size = progressIndicator.frame.size
        let inset = (fieldHeight - size.height) / 2

        progressIndicator.frame.origin = CGPoint(
            x: fieldWidth - inset - size.width,
            y: inset
        )
    }

    /// 点了 “添加” 或 “保存”：按输入得到网页，编辑时沿用原来的 id；
    /// 标题框有内容时带着这个标题交出，不再需要自动获取；空着时先不带标题交出，取到标题后补上
    /// - Parameters:
    ///   - completionHandler: 收到要加入的网页，或改好的网页
    ///   - titleHandler: 收到补上的标题，与不带标题交出的那一份网页
    private func confirm(
        completionHandler: @MainActor (WebPageReference) -> Void,
        titleHandler: @escaping @MainActor (String, WebPageReference) -> Void
    ) {
        let item = Self.webPage(
            from: addressField.stringValue,
            title: titleField.stringValue
        )

        guard case .webPage(let enteredWebPage) = item else { return }

        // 网址与标题按添加的同一规则取；编辑的是原来那一项，id 不变
        let webPage = WebPageReference(
            id: editedWebPage?.id ?? enteredWebPage.id,
            url: enteredWebPage.url,
            title: enteredWebPage.title
        )

        // 标题框有内容：带着它交出，正在进行的获取不再需要
        guard webPage.title == nil else {
            stopFetchingTitle()
            completionHandler(webPage)
            return
        }

        // 先不带标题交出，显示名是网址；之后取到的标题连同交出的这一份交给调用方，补之前核对网址。
        // 每次网址变化都取消之前的获取，此刻正在进行或随即开始的获取，取的就是交出的这个网址
        fillConfirmedWebPageTitle = {
            titleHandler($0, webPage)
        }

        completionHandler(webPage)

        // 正在进行的那一次继续，不重新发起；还在等停顿的不再等，现在就开始
        guard let pendingPause else { return }

        self.pendingPause = nil
        startFetchingTitle(of: pendingPause.url)
    }

    /// 网址变了：更新 “添加” “保存” 的可用状态；之前的停顿与获取作废，自动填进去的旧标题清空，
    /// 新网址可用时等停顿之后重新获取
    private func addressDidChange() {
        let url = enteredURL

        alert.buttons.first?.isEnabled = url != nil

        stopFetchingTitle()

        // 标题框里仍是自动填进去、用户没改过的旧标题：清空，等新网址的结果；用户自己输入的保留
        if titleField.stringValue == autofilledTitle {
            titleField.stringValue = ""
        }

        autofilledTitle = nil

        guard let url else { return }

        fetchTitleAfterPause(of: url)
    }

    /// 网址停顿一会儿不再变，才为它开始获取标题
    private func fetchTitleAfterPause(of url: URL) {
        let pauseID = UUID()

        pendingPause = (pauseID, url)

        // 停顿期间网址又变了、或者已经开始获取，这次停顿结束时编号就对不上
        waitForPause { [weak self] in
            guard
                let self,
                let pendingPause,
                pendingPause.id == pauseID
            else {
                return
            }

            self.pendingPause = nil
            startFetchingTitle(of: pendingPause.url)
        }
    }

    /// 开始获取一个网址的标题，同时开始计时：到时还没有结果就取消，当作取不到
    private func startFetchingTitle(of url: URL) {
        let fetchID = UUID()

        // 回调持有自己：不带标题交出之后提示框已经关掉，取到的标题仍要补上
        let cancel = fetchTitle(url) { [self] in
            finishFetchingTitle(fetchID, title: $0)
        }

        titleFetch = (fetchID, cancel)

        updateTitleProgress()

        // LinkPresentation 的 `timeout` 不是硬上限，由这里掐断。
        // 到时这一次已有结果或已被取消，编号就对不上，什么都不做
        waitForTimeLimit { [weak self] in
            guard
                let self,
                let titleFetch,
                titleFetch.id == fetchID
            else {
                return
            }

            // 当作取不到；之后才到的结果编号对不上，被丢掉
            titleFetch.cancel()
            finishFetchingTitle(fetchID, title: nil)
        }
    }

    /// 取消正在进行的获取，作废正在等的停顿
    private func stopFetchingTitle() {
        pendingPause = nil

        titleFetch?.cancel()
        titleFetch = nil
    }

    /// 一次获取有了结果，或到时当作取不到：去掉首尾空白，空的当作没取到；
    /// 网页已不带标题交出时补到那一项上，否则只填进空着的标题框，用户输入的内容不覆盖
    /// - Parameters:
    ///   - fetchID: 这次获取的编号
    ///   - title: 取到的标题；取不到时为 nil
    private func finishFetchingTitle(_ fetchID: UUID, title: String?) {
        // 被取消或已到时的那一次晚到的结果丢掉：LinkPresentation 取消之后仍会调用完成回调
        guard titleFetch?.id == fetchID else { return }

        titleFetch = nil

        updateTitleProgress()

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedTitle.isEmpty else { return }

        if let fillConfirmedWebPageTitle {
            fillConfirmedWebPageTitle(trimmedTitle)
            return
        }

        guard titleField.stringValue.isEmpty else { return }

        titleField.stringValue = trimmedTitle
        autofilledTitle = trimmedTitle
    }

    /// 正在获取、标题框又空着时，标题框内右端转圈，占位文字换成 “正在获取标题…”；否则恢复原样
    private func updateTitleProgress() {
        let isFetching = titleFetch != nil && titleField.stringValue.isEmpty

        if isFetching {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }

        progressIndicator.isHidden = !isFetching

        titleField.placeholderString = isFetching
            ? String(
                localized: "groups.webPageAlert.fetchingTitle",
                comment: "网页提示框里标题框的占位文字，添加与编辑共用：正在获取网页的标题"
            )
            : String(
                localized: "groups.webPageAlert.titlePlaceholder",
                comment: "网页提示框里标题框的占位文字，添加与编辑共用：标题可以留空"
            )
    }
}

// MARK: - Helpers

extension WebPageAlert {
    /// 等一段时间、再在主线程执行给它的闭包的方法：App 里的停顿与时限都这样等
    /// - Parameter duration: 等多久
    private static func waiting(
        for duration: Duration
    ) -> (@escaping @MainActor () -> Void) -> Void {
        { action in
            Task {
                try? await Task.sleep(for: duration)
                action()
            }
        }
    }
}
