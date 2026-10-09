import Foundation
import Testing

@testable import Flotilla

// MARK: - WebPageReferenceTests

/// 显示的网址：网址里的中文等要按还原后的文字给人看，百分号编码读不出来；
/// 还原后会改变网址含义、还原不出文字、显示出来看不见或打乱顺序的编码照原样
struct WebPageReferenceTests {
    /// 路径、查询参数与片段里的中文都还原，小写十六进制同样还原；emoji 也是可见的非 ASCII 字符
    @Test(arguments: [
        (
            "https://zh.wikipedia.org/wiki/%E5%BD%92%E5%B8%86",
            "https://zh.wikipedia.org/wiki/归帆"
        ),
        (
            "https://www.google.com/search?q=%E5%BD%92%E5%B8%86&hl=zh-CN",
            "https://www.google.com/search?q=归帆&hl=zh-CN"
        ),
        (
            "https://example.com/#%E5%BD%92%E5%B8%86",
            "https://example.com/#归帆"
        ),
        (
            "https://zh.wikipedia.org/wiki/%e5%bd%92%e5%b8%86",
            "https://zh.wikipedia.org/wiki/归帆"
        ),
        (
            "https://example.com/%F0%9F%98%80",
            "https://example.com/😀"
        ),
    ])
    func visibleNonASCIICharactersAreDecoded(address: String, expected: String) throws {
        #expect(try displayAddress(of: address) == expected)
    }

    /// 照原样的编码，连同原来的大小写；同一段里的中文照常还原：
    /// ASCII 字符的编码还原后会改变网址的含义，GBK 等不是 UTF-8 的编码还原不出文字，
    /// 全角空格、零宽空格与从右到左的方向控制符显示出来看不见，或会打乱文字的顺序
    @Test(arguments: [
        (
            "https://example.com/%E5%BD%92%20%E5%B8%86",
            "https://example.com/归%20帆"
        ),
        (
            "https://example.com/%E5%BD%92%2F%E5%B8%86?q=%3F%25",
            "https://example.com/归%2F帆?q=%3F%25"
        ),
        (
            "https://example.com/%B9%E9%E5%BD%92",
            "https://example.com/%B9%E9归"
        ),
        (
            "https://example.com/%E5%BD%92%E3%80%80%E5%B8%86",
            "https://example.com/归%E3%80%80帆"
        ),
        (
            "https://example.com/%E5%BD%92%E2%80%8B%E5%B8%86",
            "https://example.com/归%E2%80%8B帆"
        ),
        (
            "https://example.com/%e5%bd%92%e2%80%ae%e5%b8%86",
            "https://example.com/归%e2%80%ae帆"
        ),
    ])
    func encodingsThatWouldMisleadAreKept(address: String, expected: String) throws {
        #expect(try displayAddress(of: address) == expected)
    }

    /// 没有编码的网址原样显示；`xn--` 开头的主机名不转换成中文
    @Test(arguments: [
        "https://www.apple.com/mac/",
        "https://xn--fsqu00a.xn--0zwm56d/?q=1#top",
    ])
    func unencodedAddressIsUnchanged(address: String) throws {
        #expect(try displayAddress(of: address) == address)
    }

    /// 没有标题时显示的名称是还原后的网址；有标题时仍是标题
    @Test
    func displayNameIsTitleOrDisplayAddress() throws {
        let url = try #require(URL(string: "https://zh.wikipedia.org/wiki/%E5%BD%92%E5%B8%86"))

        let untitled = WebPageReference(id: UUID(), url: url, title: nil)
        let titled = WebPageReference(id: UUID(), url: url, title: "归帆 - 维基百科")

        #expect(untitled.displayName == "https://zh.wikipedia.org/wiki/归帆")
        #expect(titled.displayName == "归帆 - 维基百科")
    }
}

// MARK: - Private

extension WebPageReferenceTests {
    /// 这个网址的网页显示的网址
    /// - Parameter address: 网页的网址，`URL(string:)` 照原样接受的写法
    private func displayAddress(of address: String) throws -> String {
        let url = try #require(URL(string: address))

        try #require(url.absoluteString == address)

        return WebPageReference(id: UUID(), url: url, title: nil).displayAddress
    }
}
