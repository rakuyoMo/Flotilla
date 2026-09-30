import AppKit
import UniformTypeIdentifiers

// MARK: - FolderTreeCellView

/// 文件夹树的一行：图标、名称、访达里的文件夹所在的位置与状态文字；文件夹名可编辑，App、文件与网页的名称只读
final class FolderTreeCellView: NSTableCellView {
    /// 行视图的复用标识
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("FolderTreeCell")

    /// 图标边长
    private static let iconSize: CGFloat = 20

    /// 访达里的文件夹名称后的位置文字，与“不在 Dock 上”同样的灰色小字；其余各行隐藏
    ///
    /// 设置窗口里访达里的文件夹与 Flotilla 的文件夹图标相同，靠它区分
    private let locationLabel = NSTextField(labelWithString: "")

    /// 名称右侧的状态文字“不在 Dock 上”，默认隐藏
    private let notOnDockLabel = NSTextField(
        labelWithString: String(
            localized: "folders.notOnDock",
            comment: "文件夹树里 tile 不在 Dock 上的根文件夹，名称右侧的状态文字"
        )
    )

    /// 是否显示“不在 Dock 上”；只有 tile 不在 Dock 上的根文件夹这一行显示
    var showsNotOnDockLabel: Bool {
        get { !notOnDockLabel.isHidden }
        set { notOnDockLabel.isHidden = !newValue }
    }

    /// 这一行显示的位置文字；不显示时为 nil
    var locationText: String? {
        locationLabel.isHidden ? nil : locationLabel.stringValue
    }

    /// 创建图标、名称、位置文字与状态文字四个子视图并完成布局
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

        // 位置文字紧跟名称、占满剩下的宽度；两者都放不下时先截断位置，再截断名称
        locationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        locationLabel.textColor = .secondaryLabelColor
        locationLabel.lineBreakMode = .byTruncatingTail
        locationLabel.isHidden = true
        locationLabel.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        locationLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)

        notOnDockLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        notOnDockLabel.textColor = .secondaryLabelColor
        notOnDockLabel.isHidden = true
        notOnDockLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        notOnDockLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        // 隐藏的位置文字与状态文字不占位置，名称随之占满整行
        let labelRow = NSStackView(views: [nameField, locationLabel, notOnDockLabel])
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
        // 只有文件夹名可编辑：App、文件与网页的名称来自访达或浏览器
        textField?.isEditable = node.folder != nil

        // 只有访达里的文件夹这一行显示位置，行视图复用时其余各行要隐藏
        let location = Self.location(of: node.item)

        locationLabel.stringValue = location ?? ""
        locationLabel.isHidden = location == nil

        switch node.item {
        case .app(let app):
            imageView?.image = app.icon
            textField?.stringValue = app.displayName

        // 根文件夹与子文件夹都用系统的通用文件夹图标：设置窗口里不渲染文件夹的预览
        case .folder(let folder):
            imageView?.image = NSWorkspace.shared.icon(for: .folder)
            textField?.stringValue = folder.name

        case .file(let file):
            imageView?.image = file.icon
            textField?.stringValue = file.displayName

        case .webPage(let webPage):
            imageView?.image = webPage.icon
            textField?.stringValue = webPage.displayName
        }
    }
}

// MARK: - Private

extension FolderTreeCellView {
    /// 访达里的文件夹所在的位置：父目录的路径，家目录写成 `~`，例如 `~/Documents`
    /// - Returns: 不是访达里的文件夹（Flotilla 的文件夹、App、文件、文件包、网页、已删除的），或是没有父目录的 `/` 时为 nil
    private static func location(of item: FolderItem) -> String? {
        guard
            case .file(let file) = item,
            file.isFinderFolder,
            file.url.path(percentEncoded: false) != "/"
        else {
            return nil
        }

        let components = file.url
            .deletingLastPathComponent()
            .pathComponents

        let homeComponents = URL.homeDirectory.pathComponents

        // 在家目录之内：家目录这一段写成 `~`
        if components.starts(with: homeComponents) {
            return (["~"] + components.dropFirst(homeComponents.count)).joined(separator: "/")
        }

        // 第一段是根目录 `/`，其余各段以 `/` 连接
        return "/" + components.dropFirst().joined(separator: "/")
    }
}
