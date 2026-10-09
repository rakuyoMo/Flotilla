import Foundation

// MARK: - FinderFolderReadPeriods

/// 读访达文件夹时，主线程被同步读取占住的各个时段
///
/// 第一次读受保护的位置时系统弹出隐私授权框，读取等到用户回答；这期间的鼠标按下（例如点授权框的按钮）
/// 排到读取结束后才处理，要按事件自己的发生时间认出它们，
/// 不当成面板以外的点击或点击 tile
struct FinderFolderReadPeriods {
    /// 记下的各个时段，按读取的先后排列；时间都是系统启动以来的秒数，与 `NSEvent.timestamp` 同一个时钟
    private var periods: [ClosedRange<TimeInterval>] = []

    /// 记下一次读取
    /// - Parameter period: 读取开始到结束
    mutating func record(_ period: ClosedRange<TimeInterval>) {
        periods.append(period)
    }

    /// 某个时刻是否落在任一次读取期间
    ///
    /// 不只看最近一次：连点两下时，第二下可能在第一次读取结束后又进入一层、再读一次，
    /// 第一次读取期间的按下排在这之后才处理到
    /// - Parameter time: 事件发生的时间，系统启动以来的秒数
    func contains(_ time: TimeInterval) -> Bool {
        periods.contains { $0.contains(time) }
    }
}
