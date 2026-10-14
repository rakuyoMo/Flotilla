import AppKit
import Testing

@testable import Flotilla

// MARK: - AboutPanelControllerTests

/// “关于” 面板的浏览器入口：官网与源码各有入口，版权只有作者名能跳转，完整声明仍可阅读
@MainActor
struct AboutPanelControllerTests {
    /// 附加文字保留包内的完整版权，三个链接分别指向官网、项目与作者主页
    @Test
    func creditsContainRequiredLinksAndCopyright() throws {
        let infoPlist = try PrivacyUsageDescriptionTests.infoPlist()
        let copyright = try #require(infoPlist["NSHumanReadableCopyright"] as? String)
        let credits = AboutPanelController.credits(copyright: copyright)
        var destinations: [String] = []

        // 枚举实际交给 AppKit 的链接属性，防止显示文字正确却跳转到了别的地址
        credits.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: credits.length)
        ) { value, _, _ in
            guard let address = value as? String else { return }

            destinations.append(address)
        }

        #expect(destinations == [
            "https://flotilla.rakuyo.dev",
            "https://github.com/rakuyoMo/Flotilla",
            "https://github.com/rakuyoMo",
        ])

        #expect(credits.string.hasSuffix(copyright))
        #expect(copyright == "Copyright © 2026 Rakuyo. All rights reserved.")
    }

    /// 作者的链接只覆盖 “Rakuyo”，版权年份、标点与权利声明都保持普通文字
    @Test
    func authorLinkCoversOnlyAuthorName() throws {
        let infoPlist = try PrivacyUsageDescriptionTests.infoPlist()
        let copyright = try #require(infoPlist["NSHumanReadableCopyright"] as? String)
        let credits = AboutPanelController.credits(copyright: copyright)
        let authorRange = NSRange(
            try #require(credits.string.range(of: "Rakuyo")),
            in: credits.string
        )
        var effectiveRange = NSRange()

        let address = credits.attribute(
            .link,
            at: authorRange.location,
            effectiveRange: &effectiveRange
        ) as? String

        #expect(address == "https://github.com/rakuyoMo")
        #expect(effectiveRange == authorRange)
    }
}
