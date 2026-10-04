import Foundation
import Testing

@testable import Flotilla

// MARK: - FinderFolderReadPeriodsTests

/// 读访达里的文件夹期间的鼠标按下：第一次读受保护的位置时，用户点隐私授权框的按下排到读取结束后才处理，
/// 若当成面板以外的点击，刚进入的层级会随即收起；读取之外的按下必须照常收起面板、切换 tile
struct FinderFolderReadPeriodsTests {
    /// 等用户回答授权框的一次读取：第 100 秒开始，第 103.5 秒读完
    private static let promptedRead: ClosedRange<TimeInterval> = 100 ... 103.5

    /// 读取期间点授权框“允许”的按下：被忽略
    @Test
    func mouseDownDuringReadIsIgnored() {
        var periods = FinderFolderReadPeriods()
        periods.record(Self.promptedRead)

        #expect(periods.contains(102.8))
    }

    /// 读取开始与结束的那一刻也算读取期间
    @Test
    func readBoundariesAreIncluded() {
        var periods = FinderFolderReadPeriods()
        periods.record(Self.promptedRead)

        #expect(periods.contains(Self.promptedRead.lowerBound))
        #expect(periods.contains(Self.promptedRead.upperBound))
    }

    /// 读取结束之后、开始之前的按下不在读取期间：照常交给状态机，面板以外的点击收起面板、点 tile 切换
    @Test
    func mouseDownOutsideReadStillCounts() {
        var periods = FinderFolderReadPeriods()
        periods.record(Self.promptedRead)

        #expect(!periods.contains(103.6))
        #expect(!periods.contains(99.9))
    }

    /// 没有读过访达里的文件夹时，任何按下都照常处理
    @Test
    func noReadIgnoresNothing() {
        let periods = FinderFolderReadPeriods()

        #expect(!periods.contains(102.8))
    }

    /// 连点两下：第二下在第一次读取结束后又进入一层、再读一次，第一次读取期间点授权框的按下之后才处理到，仍被忽略
    @Test
    func earlierReadIsStillCovered() {
        var periods = FinderFolderReadPeriods()
        periods.record(Self.promptedRead)
        periods.record(103.6 ... 103.7)

        #expect(periods.contains(102.8))
        #expect(!periods.contains(103.8))
    }
}
