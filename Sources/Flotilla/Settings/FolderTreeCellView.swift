import AppKit
import UniformTypeIdentifiers

// MARK: - FolderTreeCellView

/// 文件夹树的一行：图标加名称；文件夹名可编辑，App 名只读
final class FolderTreeCellView: NSTableCellView {
    /// 行视图的复用标识
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FolderTreeCell")

    /// 图标边长
    private static let iconSize: CGFloat = 20

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
    /// - Parameter node: 这一行对应的节点
    func configure(with node: FolderTreeNode) {
        switch node.item {
        case .app(let app):
            imageView?.image = app.icon
            textField?.stringValue = app.displayName
            textField?.isEditable = false

        case .folder(let folder):
            // 根文件夹与子文件夹都用系统的通用文件夹图标：设置窗口里不渲染文件夹内的 App 图标
            imageView?.image = NSWorkspace.shared.icon(for: .folder)
            textField?.stringValue = folder.name
            textField?.isEditable = true
        }
    }
}
