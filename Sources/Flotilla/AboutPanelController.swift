import AppKit

// MARK: - AboutPanelController

/// 原生 “关于” 面板：由 AppKit 显示 App 信息，附上官网、源码与版权作者的链接
@MainActor
final class AboutPanelController: NSObject {
    /// 生成居中的附加文字，保留完整版权说明，仅把作者名设为链接
    /// - Parameter copyright: 当前 App 包内的版权说明
    /// - Returns: 官网、GitHub 项目与带作者链接的版权说明
    static func credits(copyright: String) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "")

        let links = [
            (
                String(
                    localized: "about.website",
                    comment: "“关于” 面板里打开官网的链接"
                ),
                "https://flotilla.rakuyo.dev"
            ),
            ("GitHub", "https://github.com/rakuyoMo/Flotilla"),
        ]

        // 每个入口独占一行；换行不带链接属性，点击目标只覆盖入口文字
        for (title, address) in links {
            text.append(NSAttributedString(
                string: title,
                attributes: [.link: address]
            ))

            text.append(NSAttributedString(string: "\n"))
        }

        text.append(NSAttributedString(string: "\n"))

        let copyrightText = NSMutableAttributedString(string: copyright)

        // 只链接版权行里的作者，年份与权利声明保持普通文字
        if let authorRange = copyright.range(of: "Rakuyo") {
            copyrightText.addAttribute(
                .link,
                value: "https://github.com/rakuyoMo",
                range: NSRange(authorRange, in: copyright)
            )
        }

        text.append(copyrightText)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineSpacing = 4

        // 使用系统字体与语义颜色，让附加文字跟随面板的深浅外观
        text.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraphStyle,
            ],
            range: NSRange(location: 0, length: text.length)
        )

        return text
    }

    /// 显示并激活 “关于” 面板；版本、构建号、名称与图标由系统从当前 App 读取
    @objc
    func show() {
        let copyright = Bundle.main.object(
            forInfoDictionaryKey: "NSHumanReadableCopyright"
        ) as? String ?? ""

        // 版权放进支持超链接的附加文字区，使作者名与其它链接一样交给默认浏览器打开
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: Self.credits(copyright: copyright),
            .init(rawValue: "Copyright"): "",
        ])

        // 面板显示后激活 Flotilla，使其能立即接受键盘与鼠标输入
        NSApp.activate(ignoringOtherApps: true)
    }
}
