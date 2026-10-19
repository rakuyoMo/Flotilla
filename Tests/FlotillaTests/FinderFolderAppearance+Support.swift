@testable import Flotilla

// MARK: - FinderFolderAppearance + Support

extension FinderFolderAppearance {
    /// 当前系统是否按外观画访达文件夹：macOS 26 起访达才按标签上色、画上 emoji 与符号
    ///
    /// 之前的系统上 `needsQuickLookIcon` 恒为 false，图标库的 `start()` 什么也不做：
    /// 依赖取图与监听的用例按它启用，读外观的用例按它给出 `needsQuickLookIcon` 的期望
    static var isSupported: Bool {
        guard #available(macOS 26, *) else { return false }

        return true
    }
}
