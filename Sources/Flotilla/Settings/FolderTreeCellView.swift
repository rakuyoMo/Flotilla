import AppKit
import UniformTypeIdentifiers

// MARK: - FolderTreeCellView

/// 文件夹树的一行：图标、名称与状态文字；文件夹名可编辑，App 名只读
final class FolderTreeCellView: NSTableCellView {
    /// 行视图的复用标识
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FolderTreeCell")

    /// 图标边长
    private static let iconSize: CGFloat = 20

    /// 名称右侧的状态文字“不在 Dock 上”，默认隐藏
    private let notOnDockLabel = NSTextField(labelWithString: "不在 Dock 上")

    /// 是否显示“不在 Dock 上”；只有 tile 不在 Dock 上的根文件夹这一行显示
    var showsNotOnDockLabel: Bool {
        get { !notOnDockLabel.isHidden }
        set { notOnDockLabel.isHidden = !newValue }
    }

    /// 创建图标、名称与状态文字三个子视图并完成布局
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        identifier = Self.reuseIdentifier

        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameField = NSTextField(labelWithString: "")
        nameField.lineBreakMode = .byTruncatingTail

        // 名称占满状态文字以外的宽度，放不下时截断名称，状态文字保持完整
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        notOnDockLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        notOnDockLabel.textColor = .secondaryLabelColor
        notOnDockLabel.isHidden = true
        notOnDockLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        notOnDockLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        // 隐藏的状态文字不占位置，名称随之占满整行
        let labelRow = NSStackView(views: [nameField, notOnDockLabel])
        labelRow.orientation = .horizontal
        labelRow.alignment = .firstBaseline
        labelRow.distribution = .fill
        labelRow.spacing = 6
        labelRow.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(labelRow)

        imageView = iconView
        textField = nameField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Self.iconSize),

            labelRow.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            labelRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            labelRow.centerYAnchor.constraint(equalTo: centerYAnchor),
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

        // 根文件夹与子文件夹都用系统的通用文件夹图标：设置窗口里不渲染文件夹内的 App 图标
        case .folder(let folder):
            imageView?.image = NSWorkspace.shared.icon(for: .folder)
            textField?.stringValue = folder.name
            textField?.isEditable = true
        }
    }
}
