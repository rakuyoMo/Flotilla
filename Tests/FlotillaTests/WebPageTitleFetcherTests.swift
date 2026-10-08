import Foundation
import Testing

@testable import Flotilla

// MARK: - WebPageTitleFetcherTests

/// 自动获取的网页标题：明文 HTTP 的网页同样取得到；LinkPresentation 拿文件名充当的标题不算标题，
/// 免得 PDF、图片等不是网页的网址被填上 “dummy” “favicon” 这样的名字
struct WebPageTitleFetcherTests {
    /// Info.plist 只为网页内容放开明文 HTTP：LinkPresentation 用网页内容加载网址，
    /// 没有这个例外时 ATS 挡下 `http://` 网址，标题一个都取不到；更宽的例外不写
    @Test
    func infoPlistAllowsPlainHTTPOnlyInWebContent() throws {
        let infoPlist = try PrivacyUsageDescriptionTests.infoPlist()

        let transportSecurity = try #require(
            infoPlist["NSAppTransportSecurity"] as? [String: Any],
            "Info.plist 缺少 NSAppTransportSecurity"
        )

        let allowsWebContent = try #require(
            transportSecurity["NSAllowsArbitraryLoadsInWebContent"] as? Bool
        )

        #expect(Set(transportSecurity.keys) == ["NSAllowsArbitraryLoadsInWebContent"])
        #expect(allowsWebContent)
    }

    /// LinkPresentation 对不是网页的网址给出的标题（macOS 27 实测）都认得出是文件名：
    /// 网址最后一段去掉一个扩展名，百分号编码解码之后，查询参数与片段不算；
    /// 跳转之后的网址由调用方给出，这里只比文件名
    @Test(arguments: [
        ("dummy", "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf"),
        ("favicon", "https://www.apple.com/favicon.ico"),
        ("picture", "https://example.com/picture.png"),
        ("plain", "https://example.com/plain.txt"),
        ("noext", "https://example.com/noext"),
        ("dir", "https://example.com/dir/"),
        ("dummy.v2", "https://example.com/dummy.v2.pdf"),
        ("my file", "https://example.com/my%20file.pdf"),
        ("中文", "https://example.com/%E4%B8%AD%E6%96%87.pdf"),
        ("中文 文件", "https://example.com/%E4%B8%AD%E6%96%87%20%E6%96%87%E4%BB%B6.png"),
        ("dummy", "https://example.com/dummy.pdf?download=1"),
        ("dummy", "https://example.com/dummy.pdf#page=2"),
    ])
    func fileNameTitleIsRecognized(title: String, address: String) throws {
        let url = try #require(URL(string: address))

        #expect(WebPageTitleFetcher.isFileName(title, of: url))
    }

    /// 网页自己的标题保留：普通网页、首页，以及只是大小写与文件名不同的标题
    @Test(arguments: [
        ("Welcome to Python.org", "https://www.python.org/"),
        ("Apple (中国大陆) - 官方网站", "https://www.apple.com/cn/"),
        ("Example Domain", "https://example.com"),
        ("Home", "https://example.com/"),
        ("About", "https://example.com/about"),
        ("Dummy", "https://example.com/dummy.pdf"),
    ])
    func pageTitleIsKept(title: String, address: String) throws {
        let url = try #require(URL(string: address))

        #expect(!WebPageTitleFetcher.isFileName(title, of: url))
    }
}
