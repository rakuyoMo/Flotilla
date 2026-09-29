import AppKit

// MARK: - DockTileBundleBuilder

/// 生成、更新、删除代表根文件夹的 stub App bundle：Dock 只能放 App 与文件，每个根文件夹靠一个 stub 出现在 Dock 上
struct DockTileBundleBuilder {
    /// App 使用的 stub 目录：`~/Library/Application Support/Flotilla/DockTiles`
    static let defaultDirectory = URL.applicationSupportDirectory
        .appending(path: "Flotilla/DockTiles", directoryHint: .isDirectory)

    /// stub 可执行文件的文件名，与 Package.swift 中的 target 名一致
    static let executableName = "FlotillaDockTile"

    /// stub 图标在 `Contents/Resources` 下的文件名（不含扩展名），同时是 `CFBundleIconFile` 的取值
    private static let iconName = "Icon"

    /// 自定义图标在 bundle 根目录下的文件名，由 `NSWorkspace.setIcon` 生成
    private static let customIconFileName = "Icon\r"

    /// Launch Services 的注册工具
    static let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// 存放所有 stub 的目录
    let directory: URL

    /// 拷进每个 stub 的 `FlotillaDockTile` 可执行文件
    let executableURL: URL

    /// stub 的 Info.plist 内容；`FlotillaFolderID` 由 stub 读取后拼出 `flotilla://folder/<id>`
    ///
    /// `CFBundleDocumentTypes` 声明 stub 能打开 App 与文件：从访达把它们拖到 tile 上时，tile 高亮为放置目标，
    /// 松手后 Launch Services 以“打开文档”的方式启动 stub
    /// - App 一项为 `Alternate`：stub 不成为 App 的默认打开方式
    /// - 文件一项必须为 `None`：`Alternate` 会让 stub 出现在访达的“打开方式”里
    /// - 实测（macOS 27）声明了 `public.data` 或 `com.apple.package`，Dock 对普通文件夹也高亮并拉起 stub，
    ///   由 Flotilla 分类时略过
    static func infoDictionary(for folder: Folder) -> [String: Any] {
        [
            "CFBundleExecutable": executableName,
            "CFBundleIdentifier": "com.rakuyo.flotilla.tile.\(folder.id.uuidString)",
            "CFBundleName": folder.name,
            "CFBundleDisplayName": folder.name,
            "CFBundleIconFile": iconName,
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": "15.0",
            "LSUIElement": true,
            "LSBackgroundOnly": true,
            "FlotillaFolderID": folder.id.uuidString,
            "CFBundleDocumentTypes": [
                [
                    "CFBundleTypeName": "Application",
                    "CFBundleTypeRole": "Viewer",
                    "LSHandlerRank": "Alternate",
                    "LSItemContentTypes": [
                        "com.apple.application",
                        "com.apple.application-bundle",
                    ],
                ],
                [
                    "CFBundleTypeName": "File",
                    "CFBundleTypeRole": "Viewer",
                    "LSHandlerRank": "None",
                    "LSItemContentTypes": [
                        "public.data",
                        "com.apple.package",
                    ],
                ],
            ],
        ]
    }
}

// MARK: - Mutation

extension DockTileBundleBuilder {
    /// 生成或更新根文件夹的 stub；名称与图标都没有变化时不动任何文件
    /// - Parameters:
    ///   - folder: 根文件夹
    ///   - icon: 按需求 2 渲染好的文件夹图标
    /// - Returns: 是否改写了 stub
    @discardableResult
    func write(folder: Folder, icon: NSImage) throws -> Bool {
        let fileManager = FileManager.default
        let bundleURL = bundleURL(for: folder)

        // 文件夹改名：原来的 stub 在自己的目录里改名，Dock 条目里的书签仍指向同一个文件
        if
            let existingURL = existingBundleURL(for: folder.id),
            existingURL.lastPathComponent != bundleURL.lastPathComponent
        {
            try fileManager.moveItem(at: existingURL, to: bundleURL)
        }

        let contentsURL = bundleURL.appending(path: "Contents", directoryHint: .isDirectory)
        let infoURL = contentsURL.appending(path: "Info.plist")
        let iconURL = contentsURL.appending(path: "Resources/\(Self.iconName).icns")
        let stubExecutableURL = contentsURL.appending(path: "MacOS/\(Self.executableName)")

        // 先把图标写到临时位置，与现有图标逐字节比对；一致时直接丢弃
        let renderedIconURL = fileManager.temporaryDirectory
            .appending(path: "Flotilla-\(UUID().uuidString).icns")

        try IconFileWriter.write(icon, to: renderedIconURL)
        defer { try? fileManager.removeItem(at: renderedIconURL) }

        // Info.plist 同样逐字节比对：XML 格式的属性列表按键排序输出，内容相同时字节一致
        let infoData = try PropertyListSerialization.data(
            fromPropertyList: Self.infoDictionary(for: folder),
            format: .xml,
            options: 0
        )

        let renderedIcon = try Data(contentsOf: renderedIconURL)

        let isInfoChanged = (try? Data(contentsOf: infoURL)) != infoData
        let isIconChanged = (try? Data(contentsOf: iconURL)) != renderedIcon

        // 缺少可执行文件或自定义图标的 stub 视为残缺，同样要重新生成
        let isIncomplete = [
            stubExecutableURL,
            bundleURL.appending(path: Self.customIconFileName),
        ].contains {
            !fileManager.fileExists(atPath: $0.path(percentEncoded: false))
        }

        guard isInfoChanged || isIconChanged || isIncomplete else { return false }

        // 按 App bundle 的结构写入三个文件；可执行文件每次都从 Flotilla.app 重新拷贝，与当前版本保持一致
        let subdirectories = [iconURL, stubExecutableURL].map { $0.deletingLastPathComponent() }
        for subdirectory in subdirectories {
            try fileManager.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        }

        try infoData.write(to: infoURL, options: .atomic)

        try replaceItem(at: iconURL, withCopyOf: renderedIconURL)
        try replaceItem(at: stubExecutableURL, withCopyOf: executableURL)

        try seal(bundleURL, iconURL: iconURL)

        return true
    }

    /// 删除根文件夹的 stub 连同它独占的目录；不存在时什么也不做
    ///
    /// 删除前先注销 stub 在 Launch Services 里的登记：登记是改写 stub 时加上的，bundle 删掉之后就注销不了了
    func remove(folderID: UUID) throws {
        let fileManager = FileManager.default
        let folderDirectory = folderDirectory(for: folderID)
        let path = folderDirectory.path(percentEncoded: false)

        guard fileManager.fileExists(atPath: path) else { return }

        // 注销失败不影响删除，登记留在 Launch Services 里只是指向一个已不存在的路径
        if let bundleURL = existingBundleURL(for: folderID) {
            try? CommandRunner.run(
                Self.lsregisterPath,
                arguments: ["-u", bundleURL.path(percentEncoded: false)]
            )
        }

        try fileManager.removeItem(at: folderDirectory)
    }
}

// MARK: - Query

extension DockTileBundleBuilder {
    /// 根文件夹对应的 stub 位置：`<directory>/<id>/<文件夹名>.app`
    ///
    /// stub 启动后，Dock 会把 tile 的名称改成 Launch Services 的显示名，也就是 bundle 的文件名，
    /// 因此文件名必须是文件夹名；同名的根文件夹靠各自独占的 `<id>` 目录区分
    func bundleURL(for folder: Folder) -> URL {
        folderDirectory(for: folder.id)
            .appending(
                path: "\(Self.fileName(for: folder)).app",
                directoryHint: .isDirectory
            )
    }

    /// 根文件夹的 stub 独占的目录：`<directory>/<id>`
    ///
    /// 目录名只取决于 id，不随文件夹改名变化；Dock 偏好按它匹配该根文件夹的 tile，stub 本身是否还在都不影响
    func folderDirectory(for folderID: UUID) -> URL {
        directory.appending(path: folderID.uuidString, directoryHint: .isDirectory)
    }

    /// 根文件夹已有 stub 的位置；还没有生成时为 nil
    func existingBundleURL(for folderID: UUID) -> URL? {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderDirectory(for: folderID),
            includingPropertiesForKeys: nil
        )) ?? []

        return urls.first { $0.pathExtension == "app" }
    }

    /// 目录中已有 stub 的根文件夹 id；目录不存在时为空
    func existingFolderIDs() -> Set<UUID> {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        return Set(
            urls.compactMap { UUID(uuidString: $0.lastPathComponent) }
        )
    }

    /// stub 所属的根文件夹：URL 形如 `<directory>/<id>/<文件夹名>.app` 时解析出 id，其它 URL 一律为 nil
    func folderID(forBundleURL url: URL) -> UUID? {
        let components = url.standardizedFileURL.pathComponents
        let directoryComponents = directory.standardizedFileURL.pathComponents

        guard
            components.count > 2,
            components.last?.hasSuffix(".app") ?? false,
            Array(components.dropLast(2)) == directoryComponents
        else {
            return nil
        }

        return UUID(uuidString: components[components.count - 2])
    }
}

// MARK: - Private

extension DockTileBundleBuilder {
    /// 重新签名，把图标设为 bundle 的自定义图标，再向 Launch Services 注册
    ///
    /// macOS 26 起，系统把 icns 形式的 App 图标装进灰色圆角底板，bundle 的自定义图标不受影响，Dock 上才能显示文件夹原本的形状
    private func seal(_ bundleURL: URL, iconURL: URL) throws {
        let bundlePath = bundleURL.path(percentEncoded: false)

        // 自定义图标写在 bundle 根目录，codesign 会拒绝为这样的 bundle 签名，先清除
        NSWorkspace.shared.setIcon(nil, forFile: bundlePath)

        // 更新 bundle 自身的修改时间，让依赖它的缓存（Launch Services、图标缓存）知道内容变了
        try FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: bundlePath
        )

        // 改动 Info.plist 与可执行文件都会让原签名失效，每次改写后重新 ad-hoc 签名
        try CommandRunner.run(
            "/usr/bin/codesign",
            arguments: ["--force", "--sign", "-", bundlePath]
        )

        guard
            let icon = NSImage(contentsOf: iconURL),
            NSWorkspace.shared.setIcon(icon, forFile: bundlePath)
        else {
            throw DockTileError.customIconFailed(path: bundlePath)
        }

        // 按改写后的 Info.plist 重新注册：Launch Services 知道 stub 能打开 App，App 拖到 tile 上时 Dock 才接受放下
        try CommandRunner.run(Self.lsregisterPath, arguments: ["-f", bundlePath])
    }

    /// 用 source 的副本替换 destination；destination 不存在时直接拷贝
    private func replaceItem(at destination: URL, withCopyOf source: URL) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: source, to: destination)
    }
}

// MARK: - Helpers

extension DockTileBundleBuilder {
    /// stub 的文件名（不含扩展名）
    ///
    /// 路径里的 `/` 换成 `:`，Launch Services 显示时会换回 `/`；名称为空时用 id，避免生成以 `.` 开头的隐藏文件
    private static func fileName(for folder: Folder) -> String {
        guard !folder.name.isEmpty else { return folder.id.uuidString }

        return folder.name.replacingOccurrences(of: "/", with: ":")
    }
}
