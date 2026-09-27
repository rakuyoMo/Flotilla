# 05 Dock 状态、拖放加入与本地化

先读 [00 总览](00-overview.md) 与 01–04 四份文档，并以 04 阶段合入后的代码为基线。本阶段交付需求 10–13：tile 被拖出 Dock 后的状态显示与重新添加、把 App 拖到 tile 上加入文件夹、界面本地化，以及设置窗口里的文件夹图标改为固定图标。

## tile 被拖出 Dock 后的状态与重新添加（需求 10）

### 同步规则

- 用户可以像其它 App 一样把 Flotilla 的 tile 拖出 Dock；拖出后 Flotilla 不再自动把它加回。
- `DockTileSynchronizer` 只在两种情况下向 Dock 添加 tile：
  1. 根文件夹是新出现的：上一次同步时它还不是根文件夹（新建的根文件夹、被拖成根文件夹的子文件夹）
     - 启动时的对账把当时的全部根文件夹都视为已同步过：Flotilla 没运行时不会有新的根文件夹出现，此时缺少 tile 的根文件夹都是被用户拖出去的
  2. 用户在设置窗口点了“添加到 Dock”
- 添加过 tile 的根文件夹，在随后的同步（通常是重启 Dock 后的复查）看到 tile 确实在 Dock 上之前一直算作“待添加”：Dock 重启后写回偏好把刚加的条目盖掉时，复查会再加一次；tile 在 Dock 上出现过、之后又不在了，才是用户拖出去的
  - 待添加的根文件夹被删除或被拖成子文件夹时，不再添加
- 这部分是纯逻辑，放在 `Dock/DockTileAdditionTracker.swift`：

  ```swift
  struct DockTileAdditionTracker {
      /// 启动时的根文件夹都视为已同步过
      init(rootFolderIDs: Set<UUID>)

      /// 用户要求把该根文件夹添加到 Dock
      mutating func request(folderID: UUID)

      /// 本次同步要添加 tile 的根文件夹：待添加的与新出现的，去掉已在 Dock 上的与已不是根文件夹的；
      /// 返回的集合就是同步之后仍待添加的集合
      mutating func folderIDsToAdd(
          rootFolderIDs: Set<UUID>,
          onDockFolderIDs: Set<UUID>
      ) -> Set<UUID>
  }
  ```

- 其余对账逻辑不变：stub 照常生成与更新（tile 不在 Dock 上的根文件夹也保留 stub，重新添加时直接引用）；已有 tile 的名称、位置与图标照常更新；多余的 tile 与 stub 照常删除。
- 每次同步结束后发出 `DockTileSynchronizer.didSynchronizeNotification`（`object` 为同步器），设置窗口据此刷新状态。

### 查询与请求

`DockTileSynchronizer` 新增两个方法：

- `func rootFolderIDsOnDock() -> Set<UUID>`：Dock 上现有 tile 对应的根文件夹 id，即 `DockPreferences.folderIDs(ofTilesIn:)` 对 stub 目录的结果
- `func addTile(for folderID: UUID)`：把该根文件夹记为待添加，并安排一次同步

### 设置窗口

- 文件夹树里，tile 不在 Dock 上的根文件夹这一行，在名称右侧显示状态文字“不在 Dock 上”：次要文字颜色（`secondaryLabelColor`）、小号系统字体；在 Dock 上的根文件夹、子文件夹与 App 都不显示。
- 底部按钮行新增“添加到 Dock”，排在“添加 App…”之后；只有选中的是 tile 不在 Dock 上的根文件夹时可用，点击后调用 `addTile(for:)`。
- 文件夹树每次重建时读取一次 `rootFolderIDsOnDock()`，行的状态与按钮的可用状态都用这一次读取的结果。
- 树在以下时机重建：`FolderStore.didChangeNotification`、`DockTileSynchronizer.didSynchronizeNotification`，以及设置窗口成为 key window 时（用户把 tile 拖出 Dock 后再点开窗口，状态才是新的）。
- `SettingsWindowController` 与 `FolderTreeViewController` 通过构造函数拿到同步器，由 `AppDelegate` 传入。Dock 集成不可用（没有 stub 可执行文件，或读不到 Dock 偏好）时同步器为 nil：不显示状态，“添加到 Dock”隐藏。

## 把 App 拖到 tile 上加入文件夹（需求 11）

### stub 声明可接收 App

- stub 的 Info.plist 增加 `CFBundleDocumentTypes`，只有一项：
  - `CFBundleTypeName = Application`
  - `CFBundleTypeRole = Viewer`
  - `LSHandlerRank = Alternate`
  - `LSItemContentTypes = [com.apple.application, com.apple.application-bundle]`
  - 取自 [macos-dock-folders](https://github.com/wjvalue/macos-dock-folders)（MIT）：从访达把 App 拖到 Dock 上的 tile 时，tile 高亮为放置目标，松手后 Launch Services 以“打开文档”的方式启动 stub；`Alternate` 让 stub 不成为 App 的默认打开方式
- stub 改写后除 `codesign` 外再执行 `lsregister -f <bundle>`（`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`），Launch Services 才知道它接收的文档类型。
- Dock 上的 tile 之间不能互相拖放：拖动 Dock 图标时整个过程由 Dock 接管，只能排序或拖出。来源只能是访达等其它 App 里的 `.app`。

### stub 的行为

- stub 改为基于 `NSApplication` 运行，仍是 `LSUIElement` + `LSBackgroundOnly` 的后台 App，不激活任何 App：
  - 由点击 tile 启动：打开 `flotilla://folder/<id>`，与 02 一致
  - 由拖放启动：AppKit 在 `applicationDidFinishLaunching` 之前经 `application(_:open:)` 送来被拖的 URL，可能分多次送到，全部收齐后在 `applicationDidFinishLaunching` 里打开 `flotilla://folder/<id>/apps?path=<路径>&path=<路径>`：每个被拖的项一个 `path` 查询项，取值为它的 POSIX 路径，由 `URLComponents` 编码
  - 其余不变：`activates = false`，等到回调（最多 5 秒）后退出；缺少 id 或打开失败时记日志并以非零状态退出
- 同一次拖放的事件可能被系统重复送达（参考项目实测）；stub 每次启动只发一个 URL，重复到达的 URL 由 Flotilla 侧 `addApps` 的去重吸收。

### Flotilla 侧

- 新类型 `Dock/DockTileRequest.swift`：stub 通过 URL 向 Flotilla 发出的请求，取代 `AppDelegate.folderID(from:)`

  ```swift
  enum DockTileRequest: Equatable {
      /// 展开或收起根文件夹的面板
      case toggleFolder(UUID)

      /// 把这些 App 加入根文件夹
      case addApps(folderID: UUID, appURLs: [URL])

      init?(url: URL)
  }
  ```

  - `flotilla://folder/<uuid>` → `.toggleFolder`
  - `flotilla://folder/<uuid>/apps?path=…&path=…` → `.addApps`：`path` 解码后按目录 URL（`URL(filePath:directoryHint: .isDirectory)`）给出，顺序与查询项一致；没有任何 `path` 时视为无法识别
  - 其它 URL 一律为 nil
- `AppDelegate.application(_:open:)`：`.toggleFolder` 交给 `DockFolderPresenter`；`.addApps` 先只保留 App bundle（内容类型符合 `.applicationBundle`），再交给 `FolderStore.shared.addApps(_:to:)`；整个过程不激活 Flotilla。
  - App bundle 的判断与设置窗口从访达拖入时相同，抽到 `AppReference.isApplicationBundle(_ url: URL) -> Bool` 供两处共用
- 加入之后，文件夹树、tile 图标与面板都按既有的变更通知更新，不另加提示。

## 界面本地化（需求 12）

- 支持英文、简体中文、繁体中文、日文、韩文，跟随系统语言与“系统设置 › 通用 › 语言与地区 › 应用程序”里对 Flotilla 的单独设置；其它语言回落到英文。
- 资源：`Sources/Flotilla/Resources/<语言>.lproj/Localizable.strings`，语言目录为 `en`、`zh-Hans`、`zh-Hant`、`ja`、`ko`。
  - `Package.swift` 把 `Resources` 从编译中排除；`Scripts/bundle.sh` 把五个 `.lproj` 拷入 `Flotilla.app/Contents/Resources/`
  - `Info.plist` 增加 `CFBundleDevelopmentRegion = en`
- 代码里所有用户可见的文字改为 `String(localized:comment:)`，键见下表；日志、`#warning` 与注释仍是中文，不本地化。
- 五张表的键完全一致，缺一个都不行：进程只选一种语言，缺键时显示的是键名而不是英文。
- 用词对照系统自带 App 在各语言下的同名功能（“设置…”“退出”“撤销”“拷貝”“取り消す”“오려두기”等）。

| 键 | en | zh-Hans | zh-Hant | ja | ko |
|---|---|---|---|---|---|
| `mainMenu.quit` | Quit Flotilla | 退出 Flotilla | 結束 Flotilla | Flotillaを終了 | Flotilla 종료 |
| `mainMenu.edit` | Edit | 编辑 | 編輯 | 編集 | 편집 |
| `mainMenu.undo` | Undo | 撤销 | 還原 | 取り消す | 실행 취소 |
| `mainMenu.redo` | Redo | 重做 | 重做 | やり直す | 실행 복귀 |
| `mainMenu.cut` | Cut | 剪切 | 剪下 | カット | 오려두기 |
| `mainMenu.copy` | Copy | 复制 | 拷貝 | コピー | 복사하기 |
| `mainMenu.paste` | Paste | 粘贴 | 貼上 | ペースト | 붙이기 |
| `mainMenu.selectAll` | Select All | 全选 | 全選 | すべてを選択 | 전체 선택 |
| `statusBar.settings` | Settings… | 设置… | 設定… | 設定… | 설정… |
| `settings.windowTitle` | Flotilla Settings | Flotilla 设置 | Flotilla 設定 | Flotillaの設定 | Flotilla 설정 |
| `folders.sectionTitle` | Folders | 文件夹 | 檔案夾 | フォルダ | 폴더 |
| `folders.newFolder` | New Folder | 新建文件夹 | 新增檔案夾 | 新規フォルダ | 새로운 폴더 |
| `folders.untitledFolder` | Untitled Folder | 未命名文件夹 | 未命名檔案夾 | 名称未設定フォルダ | 제목 없는 폴더 |
| `folders.addApps` | Add Apps… | 添加 App… | 加入 App… | アプリを追加… | 앱 추가… |
| `folders.addToDock` | Add to Dock | 添加到 Dock | 加入 Dock | Dockに追加 | Dock에 추가 |
| `folders.notOnDock` | Not in Dock | 不在 Dock 上 | 不在 Dock 上 | Dockにありません | Dock에 없음 |
| `folders.remove` | Delete | 删除 | 刪除 | 削除 | 삭제 |
| `general.sectionTitle` | General | 通用 | 一般 | 一般 | 일반 |
| `general.previewIconCount` | App icons shown in folder icon: | 文件夹图标内显示的 App 图标数量： | 檔案夾圖像內顯示的 App 圖像數量： | フォルダアイコンに表示するアプリアイコンの数： | 폴더 아이콘에 표시할 앱 아이콘 수: |
| `general.accessibility` | Accessibility permission: | 辅助功能权限： | 輔助使用權限： | アクセシビリティの権限： | 손쉬운 사용 권한: |
| `general.accessibilityGranted` | Granted | 已授权 | 已授權 | 許可済み | 허용됨 |
| `general.accessibilityNotGranted` | Not granted | 未授权 | 未授權 | 未許可 | 허용되지 않음 |
| `general.openSystemSettings` | Open System Settings | 打开系统设置 | 打開系統設定 | システム設定を開く | 시스템 설정 열기 |
| `panel.back` | Back | 返回 | 返回 | 戻る | 뒤로 |

- `panel.back` 是面板返回按钮的辅助功能标签；状态栏图标的辅助功能描述“Flotilla”是 App 名，不本地化。

## 设置窗口的文件夹图标（需求 13）

- 文件夹树里文件夹行的图标改为系统的通用文件夹图标（`NSWorkspace.shared.icon(for: .folder)`），根文件夹与子文件夹相同，不再用 `FolderIconRenderer` 渲染，也不随预览数量与系统外观变化。
- `FolderTreeCellView` 不再持有文件夹与预览数量，也不再在 `viewDidChangeEffectiveAppearance` 里重新渲染；`FolderTreeViewController` 不再依赖 `Preferences`，也不再订阅 `Preferences.didChangeNotification`。
- App 行仍用 `AppReference.icon`。
- 需求 2 的预览图标与外观跟随只影响 Dock 上的 tile 与面板里的子文件夹。

## 单元测试

- `DockTileAdditionTracker`：启动时缺少 tile 的根文件夹不添加；新出现的根文件夹添加；添加过的在看到 tile 之前保持待添加，看到之后再消失不再添加；用户请求的添加；待添加的被删除或不再是根文件夹时不添加
- `DockTileRequest`：两种 URL 的解析，`path` 里的空格与中文，多个 `path` 保持顺序；scheme、host、层级、id 不符或没有 `path` 的 URL 一律为 nil（取代 `FolderURLParsingTests`）
- stub 的 Info.plist 含上述 `CFBundleDocumentTypes`
- 本地化：五张 `Localizable.strings` 都能解析、键集合完全相同、没有空值；代码里 `String(localized:` 引用的每个键都在表里，表里的每个键都被代码引用
- 设置窗口树的文件夹图标不再随外观变化，对应的测试删除

## 文档回写

- 00：需求清单、模块划分表与阶段列表
- 01：设置窗口文件夹行的图标；Info.plist 一节里“Flotilla 自己没有本地化资源”的说法
- 02：stub 的 Info.plist 键与行为；同步器的对账规则、添加 tile 的条件与复查的含义；信号链路加上拖放
- 04：端到端验证第 10 步不再包含设置窗口的图标
- `README.md`：把 App 拖到 tile 上、tile 拖出 Dock 后的状态与“添加到 Dock”、支持的语言
- `AGENTS.md`：目录结构表加上 `Resources/`，需求文档范围改为 01–05

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过；`build/Flotilla.app/Contents/Resources/` 下有五个 `.lproj`
- 真实 Dock 上：
  - 把 tile 拖出 Dock 后，Flotilla 不加回；设置窗口里该根文件夹显示“不在 Dock 上”，选中后“添加到 Dock”可用，点击后 tile 回到 Dock、状态消失
  - 新建根文件夹仍自动出现在 Dock 上；重启 Flotilla 后被拖出的 tile 仍不加回
  - 从访达把一个或多个 App 拖到 tile 上：tile 高亮，松手后 App 出现在该文件夹里；前台 App 保持前台；拖非 App 的文件不接收
  - 系统语言或 Flotilla 的单独语言设置切到五种语言之一时，菜单、设置窗口与面板返回按钮的辅助功能标签都换成对应语言；其它语言显示英文
  - 设置窗口里文件夹行显示系统文件夹图标，切换外观不重绘
