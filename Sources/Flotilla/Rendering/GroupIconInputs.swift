// MARK: - GroupIconInputs

/// 组图标的输入：底板的外观与按顺序参与预览的项
///
/// 输入相同的两次渲染，底板与每一格画的都是同一项；同步器据此跳过输入没变的根组，不重新渲染、比对它的图标。
/// 预览数量只通过取到哪几项影响图标，不单独记
struct GroupIconInputs: Equatable {
    /// 底板按哪种外观取色
    let appearance: GroupIconAppearance

    /// 按顺序参与预览的项，见 `GroupIconRenderer.previewItems(of:previewIconCount:)`
    let previewItems: [GroupItem]

    /// 按组图标的渲染参数取出它的输入
    /// - Parameters:
    ///   - group: 要渲染的组
    ///   - previewIconCount: 预览数量上限，与渲染时传给 `GroupIconRenderer` 的相同
    ///   - appearance: 底板按哪种外观取色
    init(
        group: Group,
        previewIconCount: Int,
        appearance: GroupIconAppearance
    ) {
        self.appearance = appearance

        previewItems = GroupIconRenderer.previewItems(
            of: group,
            previewIconCount: previewIconCount
        )
    }
}
