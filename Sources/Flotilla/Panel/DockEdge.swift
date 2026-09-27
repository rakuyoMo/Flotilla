import CoreGraphics

// MARK: - DockEdge

/// Dock 所贴的屏幕边，面板的尾巴长在面向它的那条边上
enum DockEdge: Equatable {
    /// 屏幕底部
    case bottom

    /// 屏幕左侧
    case left

    /// 屏幕右侧
    case right

    /// 按 Dock 偏好里 `orientation` 的取值创建
    /// - Parameter orientation: `bottom`、`left` 或 `right`；缺省或无法识别时按底部处理，与 Dock 的默认位置一致
    init(orientation: String?) {
        switch orientation {
        case "left":
            self = .left

        case "right":
            self = .right

        default:
            self = .bottom
        }
    }
}

// MARK: - Geometry

extension DockEdge {
    /// Dock 所贴的那条屏幕边在矩形上的对应边
    var rectEdge: CGRectEdge {
        switch self {
        case .bottom:
            .minYEdge

        case .left:
            .minXEdge

        case .right:
            .maxXEdge
        }
    }
}
