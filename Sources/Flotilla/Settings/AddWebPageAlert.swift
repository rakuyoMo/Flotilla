import AppKit

// MARK: - AddWebPageAlert

/// “添加网页…” 的提示框：输入网址，点 “添加” 后得到要加入文件夹的网页
///
/// 输入不是可用的网址时 “添加” 禁用，随输入实时更新：确认之后不会再报错，也不必再弹第二个提示框
@MainActor
final class AddWebPageAlert: NSObject {
    /// 提示框正文距左右两边的距离，实测（macOS 27）；输入框按它与正文左右对齐
    private static let textInset: CGFloat = 20

    /// 提示框：标题、说明、“添加” “取消” 两个按钮，输入框作为附件
    let alert = NSAlert()

    /// 输入网址的单行输入框
    private let textField = NSTextField(string: "")

    /// 配好提示框的文字、按钮与输入框；刚弹出时输入为空，“添加” 禁用
    override init() {
        super.init()

        alert.messageText = String(
            localized: "folders.webPageAlert.message",
            comment: "“添加网页…” 提示框的标题"
        )

        alert.informativeText = String(
            localized: "folders.webPageAlert.informative",
            comment: "“添加网页…” 提示框的说明文字，位于输入框上方"
        )

        configureButtons()
        configureTextField()
    }

    /// 把输入的文字变成要加入的网页，没写 scheme 时像浏览器地址栏那样补上 `https://`；不是可用的网址时为 nil
    ///
    /// 除此之外保持输入的样子：大小写、末尾斜杠、`www.` 都不改
    /// - Parameter input: 输入框里的文字
    static func webPage(from input: String) -> FolderItem? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // 中间还有空白时多半是把一句话当成了网址
        guard
            !text.isEmpty,
            !text.contains(where: \.isWhitespace)
        else {
            return nil
        }

        // 不补 scheme 时，`localhost:8080` 会被解析成 scheme 为 `localhost` 的网址
        let address = text.contains("://") ? text : "https://" + text

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
        return FolderItem(url: url, title: nil)
    }

    /// 以 sheet 挂在窗口上弹出；点 “添加” 时把输入的网页交给 completionHandler，点 “取消” 或按 Esc 时什么都不做
    /// - Parameters:
    ///   - window: 提示框挂在这个窗口上
    ///   - completionHandler: 收到要加入的网页，标题为 nil
    func beginSheetModal(
        for window: NSWindow,
        completionHandler: @escaping @MainActor (FolderItem) -> Void
    ) {
        // 弹出期间由完成回调持有自己：输入框的 delegate 是弱引用
        alert.beginSheetModal(for: window) { [self] response in
            guard
                response == .alertFirstButtonReturn,
                let webPage = Self.webPage(from: textField.stringValue)
            else {
                return
            }

            completionHandler(webPage)
        }
    }
}

// MARK: NSTextFieldDelegate

extension AddWebPageAlert: NSTextFieldDelegate {
    /// 输入变化时更新 “添加” 的可用状态，键入与粘贴都会走到这里
    func controlTextDidChange(_: Notification) {
        alert.buttons.first?.isEnabled = Self.webPage(from: textField.stringValue) != nil
    }
}

// MARK: - Private

extension AddWebPageAlert {
    /// 加上 “添加” 与 “取消”：提示框把第一个按钮设为默认按钮，回车触发 “添加”；
    /// 只有英文标题 “Cancel” 会自动得到 Esc，其它语言的 “取消” 要显式设上
    private func configureButtons() {
        let addButton = alert.addButton(
            withTitle: String(
                localized: "folders.webPageAlert.add",
                comment: "“添加网页…” 提示框的按钮：把输入的网页加入文件夹"
            )
        )

        addButton.isEnabled = false

        let cancelButton = alert.addButton(
            withTitle: String(
                localized: "folders.webPageAlert.cancel",
                comment: "“添加网页…” 提示框的按钮：关闭提示框，什么都不加入"
            )
        )

        cancelButton.keyEquivalent = "\u{1b}"
    }

    /// 把输入框放在说明文字下方，与正文左右对齐，弹出时就是第一响应者
    ///
    /// 正文宽度随提示框的宽度变化，提示框又随按钮标题变宽：
    /// 先按没有附件的样子排一次，得到提示框的宽度，再扣掉正文两侧的距离
    private func configureTextField() {
        textField.delegate = self

        alert.layout()

        textField.frame = NSRect(
            x: 0,
            y: 0,
            width: alert.window.contentLayoutRect.width - 2 * Self.textInset,
            height: textField.intrinsicContentSize.height
        )

        alert.accessoryView = textField

        // 弹出后可以直接打字或粘贴，不必先点输入框
        alert.window.initialFirstResponder = textField
    }
}
