import Foundation
import Testing

// MARK: - WebPageTitleFetcherTests

/// 自动获取的网页标题：明文 HTTP 的网页同样取得到
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
}
