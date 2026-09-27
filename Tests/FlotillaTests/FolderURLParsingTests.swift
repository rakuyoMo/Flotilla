import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderURLParsingTests

/// Dock tile 通过 `flotilla://folder/<uuid>` 通知 Flotilla；只有这一种形式会触发面板
@MainActor
struct FolderURLParsingTests {
    /// 合法的 URL 解析出其中的根文件夹 id
    @Test
    func parsesFolderURL() throws {
        let id = UUID()
        let url = try #require(URL(string: "flotilla://folder/\(id.uuidString)"))

        #expect(AppDelegate.folderID(from: url) == id)
    }

    /// scheme、host、路径层级或 id 不符合约定的 URL 一律忽略
    @Test(arguments: [
        "https://folder/\(UUID().uuidString)",
        "flotilla://tile/\(UUID().uuidString)",
        "flotilla://folder/\(UUID().uuidString)/extra",
        "flotilla://folder/not-a-uuid",
        "flotilla://folder/",
        "flotilla://folder",
    ])
    func ignoresOtherURLs(string: String) throws {
        let url = try #require(URL(string: string))

        #expect(AppDelegate.folderID(from: url) == nil)
    }
}
