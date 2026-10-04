import AppKit
import Testing

@testable import Flotilla

// MARK: - FolderNavigationHeaderViewTests

/// 标题区的标题按原生的位置摆放：与原生逐像素对照时，标题差 0.5 pt 就能看出
@MainActor
struct FolderNavigationHeaderViewTests {
    /// 标题中心与原生相同：原生标题框宽为文字宽向上取整再加 1 pt，左边取整到点
    ///
    /// 期望值是原生屏上实测的标题框中心：框宽为奇数（“A” 11 pt、“验证标题” 57 pt）时比主体中心偏左 0.5 pt，
    /// 为偶数（“Hello World” 76 pt、“Long Name Test” 106 pt）时正好居中
    @Test(
        arguments: [
            ("A", 162.0, 80.5),
            ("Hello World", 162.0, 81.0),
            ("验证标题", 546.0, 272.5),
            ("Long Name Test", 674.0, 337.0),
        ]
    )
    func titleCenterMatchesNative(title: String, bodyWidth: CGFloat, nativeCenter: CGFloat) throws {
        let label = try layoutTitle(title, bodyWidth: bodyWidth)

        #expect(label.frame.midX == nativeCenter)
    }

    /// 标题基线距面板主体顶边 23 pt，根层级与子层级相同
    @Test(arguments: [false, true])
    func titleBaselineMatchesNative(hasBackButton: Bool) throws {
        let label = try layoutTitle("子目录", bodyWidth: 290, hasBackButton: hasBackButton)

        #expect(label.frame.minY + label.firstBaselineOffsetFromTop == 23)
    }
}

// MARK: - Private

extension FolderNavigationHeaderViewTests {
    /// 按面板主体宽度建标题区并完成布局，返回其中的标题
    /// - Parameters:
    ///   - title: 标题文字
    ///   - bodyWidth: 面板主体的宽度，即标题区的宽度
    ///   - hasBackButton: 是否是子层级（显示返回按钮）
    private func layoutTitle(
        _ title: String,
        bodyWidth: CGFloat,
        hasBackButton: Bool = false
    ) throws -> FolderPanelLabel {
        let header = FolderNavigationHeaderView(
            title: title,
            backHandler: hasBackButton ? { } : nil
        )

        header.frame = CGRect(
            x: 0,
            y: 0,
            width: bodyWidth,
            height: FolderPanelMetrics.headerHeight
        )

        header.layoutSubtreeIfNeeded()

        return try #require(header.subviews.compactMap { $0 as? FolderPanelLabel }.first)
    }
}
