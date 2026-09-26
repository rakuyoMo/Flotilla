import Foundation
import Testing

@testable import Flotilla

// MARK: - PreferencesTests

/// 预览图标数的默认值与夹取：Dock 图标的 2×2 网格放不下超出范围的值
@MainActor
final class PreferencesTests {
    /// 本用例独占的临时目录
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "FlotillaTests-\(UUID().uuidString)")

    /// 本用例独占的 `UserDefaults`
    private let defaults: UserDefaults

    /// 以临时目录下的绝对路径作 suite 名称，设置写进该目录的 plist，不碰真实的偏好设置
    init() throws {
        let suiteName = directory.appending(path: "defaults").path(percentEncoded: false)
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    /// 删除本用例的临时目录
    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 从未设置过时显示满 4 个
    @Test
    func defaultsToMaximum() {
        let preferences = Preferences(defaults: defaults)

        #expect(preferences.previewIconCount == 4)
    }

    /// 写入超出范围的值时夹到两端
    @Test
    func clampsWrites() {
        let preferences = Preferences(defaults: defaults)

        preferences.previewIconCount = 9
        #expect(preferences.previewIconCount == 4)

        preferences.previewIconCount = -3
        #expect(preferences.previewIconCount == 0)
    }

    /// 存储里已有超出范围的值时，读出的值也夹到两端
    @Test
    func clampsStoredValues() {
        defaults.set(12, forKey: "previewIconCount")

        #expect(Preferences(defaults: defaults).previewIconCount == 4)
    }

    /// 值确有变化时才发通知，并且新值写入存储：Dock 图标会随通知重新渲染
    @Test
    func notifiesOnlyOnChange() async {
        let preferences = Preferences(defaults: defaults)

        await confirmation(expectedCount: 1) { changed in
            let observer = NotificationCenter.default.addObserver(
                forName: Preferences.didChangeNotification,
                object: preferences,
                queue: nil
            ) { _ in
                changed()
            }

            defer { NotificationCenter.default.removeObserver(observer) }

            preferences.previewIconCount = 4
            preferences.previewIconCount = 2
            preferences.previewIconCount = 2
        }

        #expect(Preferences(defaults: defaults).previewIconCount == 2)
    }
}
