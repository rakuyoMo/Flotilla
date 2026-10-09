import AppKit

// MARK: - GroupTreeCellView

/// 组树的一行：图标、名称、访达文件夹的位置或网页的网址，以及状态文字；
/// 组名可编辑，App、文件与网页的名称只读
final class GroupTreeCellView: NSTableCellView {
    /// 行视图的复用标识
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("GroupTreeCell")

    /// 行首图标的边长（pt）
    private static let iconSize: CGFloat = 20

    /// 组这一行的黄色文件夹图标（需求 35）：所有组行共用，只着色一次
    private static let groupIcon = YellowFolderIconRenderer.render(pointSize: iconSize)

    /// 名称后的灰色小字，与 “不在 Dock 上” 样式相同：访达文件夹的位置或网页的网址；其余各行隐藏
    private let locationLabel = NSTextField(labelWithString: "")

    /// 名称右侧的状态文字 “不在 Dock 上”，默认隐藏
    private let notOnDockLabel = NSTextField(
        labelWithString: String(
            localized: "groups.notOnDock",
            comment: "组树里 tile 不在 Dock 上的根组，名称右侧的状态文字"
        )
    )

    /// 是否显示 “不在 Dock 上”；只有被拖出 Dock 的根组这一行显示
    var showsNotOnDockLabel: Bool {
        get { !notOnDockLabel.isHidden }
        set { notOnDockLabel.isHidden = !newValue }
    }

    /// 这一行名称后显示的位置或网址；不显示时为 nil
    var locationText: String? {
        locationLabel.isHidden ? nil : locationLabel.stringValue
    }

    /// 创建图标、名称、位置或网址、状态文字四个子视图并完成布局
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        identifier = Self.reuseIdentifier

        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameField = NSTextField(labelWithString: "")
        nameField.lineBreakMode = .byTruncatingTail

        // 位置或网址隐藏时名称占满状态文字以外的宽度；
        // 放不下时截断名称，状态文字保持完整
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        locationLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        locationLabel.textColor = .secondaryLabelColor
        locationLabel.isHidden = true

        // 在中间省略：位置开头的 `~/` 与离它最近的那一级目录，
        // 网址的开头与末尾，都留着
        locationLabel.lineBreakMode = .byTruncatingMiddle

        // 位置或网址紧跟名称、占满剩下的宽度；两者都放不下时先截断它，再截断名称
        locationLabel.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        locationLabel.setContentCompressionResistancePriority(.defaultLow - 1, for: .horizontal)

        notOnDockLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        notOnDockLabel.textColor = .secondaryLabelColor
        notOnDockLabel.isHidden = true
        notOnDockLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        notOnDockLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        // 隐藏的位置或网址与状态文字不占位置，名称随之占满整行
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
        fatalError("不支持从归档解码")
    }

    /// 用节点内容填充这一行
    /// - Parameter node: 这一行对应的节点
    func configure(with node: GroupTreeNode) {
        // 只有组名可编辑：App、文件与网页的名称来自访达或浏览器
        textField?.isEditable = node.group != nil

        // 只有访达文件夹与网页的行可能显示，行视图复用时其余各行要隐藏
        let location = Self.location(of: node.item)

        locationLabel.stringValue = location ?? ""
        locationLabel.isHidden = location == nil

        switch node.item {
        case .app(let app):
            imageView?.image = app.icon
            textField?.stringValue = app.displayName

        // 根组与子组都是固定的黄色文件夹：设置窗口里不渲染组的预览，与蓝色的访达文件夹区分开
        case .group(let group):
            imageView?.image = Self.groupIcon
            textField?.stringValue = group.name

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

extension GroupTreeCellView {
    /// 名称后的灰色小字：访达文件夹所在的位置，或网页的网址
    ///
    /// 位置是父目录的路径，家目录写成 `~`，例如 `~/Documents`；网址是显示的网址，中文等按还原后的文字显示
    /// - Returns: 组、App、文件、文件包、已删除的访达文件夹、没有父目录的 `/`，以及名称就是网址的网页为 nil
    private static func location(of item: GroupItem) -> String? {
        // 没有标题时名称就是网址，标题恰好与网址相同时同理：不再重复一遍
        if case .webPage(let webPage) = item {
            let address = webPage.displayAddress

            return webPage.displayName == address ? nil : address
        }

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
