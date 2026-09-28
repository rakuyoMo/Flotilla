// MARK: - AppIconVariant

/// Flotilla 在运行时换上的 App 图标：都以夜间版为底，按“图标与小组件样式”的深色子变体处理
///
/// Dock 对运行时设置的图标原样显示、不做任何样式处理（macOS 27 实测），所以透明、色调的深色子变体要先处理好再设
enum AppIconVariant {
    /// 夜间版原样：深色样式
    case night

    /// 夜间版去色：透明样式的深色子变体
    case clearNight

    /// 夜间版按当前色调颜色着色：色调样式的深色子变体
    case tintedNight
}
