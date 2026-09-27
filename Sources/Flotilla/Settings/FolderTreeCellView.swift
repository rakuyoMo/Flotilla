import AppKit

// MARK: - FolderTreeCellView

/// 文件夹树的一行：图标加名称；文件夹名可编辑，App 名只读
final class FolderTreeCellView: NSTableCellView {
    /// 行视图的复用标识
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FolderTreeCell")

    /// 图标边长
    private static let iconSize: CGFloat = 20

    /// 这一行显示的文件夹，App 行为 nil；系统外观变化时按它重新渲染图标
    private var folder: Folder?

    /// 文件夹图标内叠加的 App 图标数量
    private var previewIconCount = 0

    /// 创建图标与名称两个子视图并完成布局
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        identifier = Self.reuseIdentifier

        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameField = NSTextField(labelWithString: "")
        nameField.lineBreakMode = .byTruncatingTail
        nameField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameField)

        imageView = iconView
        textField = nameField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// 行视图完全由代码构建，不支持从归档解码
    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 用节点内容填充这一行
    /// - Parameters:
    ///   - node: 这一行对应的节点
    ///   - previewIconCount: 文件夹图标内叠加的 App 图标数量
    func configure(with node: FolderTreeNode, previewIconCount: Int) {
        self.previewIconCount = previewIconCount

        switch node.item {
        case .app(let app):
            folder = nil

            imageView?.image = app.icon
            textField?.stringValue = app.displayName
            textField?.isEditable = false

        case .folder(let folder):
            self.folder = folder
            updateFolderIcon()

            textField?.stringValue = folder.name
            textField?.isEditable = true
        }
    }

    /// 系统外观变化时，文件夹图标换成对应外观的底板
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()

        updateFolderIcon()
    }
}

// MARK: - Private

extension FolderTreeCellView {
    /// 按这一行当前的外观渲染文件夹图标；App 行不动
    private func updateFolderIcon() {
        guard let folder else { return }

        imageView?.image = FolderIconRenderer.render(
            folder: folder,
            previewIconCount: previewIconCount,
            pointSize: Self.iconSize,
            appearance: FolderIconAppearance(effectiveAppearance)
        )
    }
}
