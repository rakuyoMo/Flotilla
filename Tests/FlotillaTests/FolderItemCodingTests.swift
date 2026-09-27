import Foundation
import Testing

@testable import Flotilla

// MARK: - FolderItemCodingTests

/// 文件夹树的 JSON 编解码：持久化文件要能完整还原任意深度的嵌套结构
struct FolderItemCodingTests {
    /// 三层嵌套、App 与子文件夹混排的结构，编码后再解码必须与原值一致
    @Test
    func nestedTreeRoundTrips() throws {
        let innermost = Folder(
            id: UUID(),
            name: "最内层",
            items: [.app(makeApp("Chess"))]
        )

        let middle = Folder(
            id: UUID(),
            name: "中间层",
            items: [
                .folder(innermost),
                .app(makeApp("Calendar")),
            ]
        )

        let root = Folder(
            id: UUID(),
            name: "根",
            items: [
                .app(makeApp("Calculator")),
                .folder(middle),
            ]
        )

        let data = try JSONEncoder().encode([root])
        let decoded = try JSONDecoder().decode([Folder].self, from: data)

        #expect(decoded == [root])
    }

    /// 每一项都带显式的类型标签，读者不看代码也能分辨 App 与子文件夹
    @Test
    func itemsCarryExplicitTypeTag() throws {
        let items: [FolderItem] = [
            .app(makeApp("Chess")),
            .folder(Folder(id: UUID(), name: "子文件夹", items: [])),
        ]

        let data = try JSONEncoder().encode(items)
        let object = try JSONSerialization.jsonObject(with: data)
        let objects = try #require(object as? [[String: Any]])

        #expect(objects.map { $0["type"] as? String } == ["app", "folder"])
    }

    /// 未知的类型标签视为数据损坏，而不是被静默丢弃
    @Test
    func unknownTypeTagFailsToDecode() {
        let json = Data(#"[{"type": "widget", "id": "\#(UUID().uuidString)"}]"#.utf8)

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([FolderItem].self, from: json)
        }
    }

    /// 引用 `/System/Applications` 下的系统 App
    private func makeApp(_ name: String) -> AppReference {
        AppReference(id: UUID(), url: URL(filePath: "/System/Applications/\(name).app"))
    }
}
