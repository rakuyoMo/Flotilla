# 05 Dock 状态、拖放加入与本地化

先读 [00 总览](00-overview.md) 与 01–04 四份文档，并以 04 阶段合入后的代码为基线。本阶段交付需求 10–13：tile 被拖出 Dock 后的状态显示与重新添加、把 App 拖到 tile 上加入文件夹、界面本地化，以及设置窗口里的文件夹图标用固定图标。

## tile 被拖出 Dock 后的状态与重新添加（需求 10）

### 同步规则

- 用户可以像其它 App 一样把 Flotilla 的 tile 拖出 Dock；拖出后 Flotilla 不再自动把它加回。
- `DockTileSynchronizer` 只在两种情况下向 Dock 添加 tile：
  1. 根文件夹是新出现的：上一次同步时它还不是根文件夹（新建的根文件夹、被拖成根文件夹的子文件夹）
     - 启动时的同步把当时的全部根文件夹都视为已同步过：Flotilla 没运行时不会有新的根文件夹出现，此时缺少 tile 的根文件夹都是被用户拖出去的
  2. 用户在设置窗口点了 “添加到 Dock”
- 添加过 tile 的根文件夹先算作 “待添加”，直到确认 tile 已经加上。添加 tile 后同步器重启 Dock，旧 Dock 退出后核对新 Dock 读到的偏好（见 02 的 “Dock 重启后的核对”）：
  - 核对通过：新拉起的 Dock 读到了期望状态，此刻 Dock 偏好里有 tile 的根文件夹确认加上，不再待添加；此后新 Dock 自己的写回也保留这些条目
  - 旧 Dock 终止时的写回抹掉了刚加的 tile 时，核对里立即补写，补写赶在新 Dock 读取偏好之前才算通过
  - 核对放弃（一次同步重启 Dock 3 次，补写仍晚于新 Dock 读取）时仍待添加，之后的同步再加
  - 同步看到 tile 在 Dock 上时同样不再待添加
- 不再待添加之后 tile 不在 Dock 上，就是用户拖出去的：之后的同步都不加回
  - 用户在 tile 出现后立即把它拖出同样不加回
- 待添加的根文件夹被删除或被拖成子文件夹时，不再添加
- 在设置窗口新建的根文件夹，在输入名称期间搁置：不添加 tile，也不算被拖出；名称编辑结束（回车确认、点别处提交、Esc 取消）后解除搁置，按新出现的根文件夹添加，tile 带着最终名称出现，Dock 只重启一次
  - 新建子文件夹不涉及 tile，不搁置；拖放等其它途径出现的根文件夹也不搁置
  - 搁置只在内存里：搁置期间退出 Flotilla，下次启动时它与其它根文件夹一样视为已同步过，没有 tile，显示 “不在 Dock 上”
- 这部分是纯逻辑，放在 `Dock/DockTileAdditionTracker.swift`：

  ```swift
  struct DockTileAdditionTracker {
      /// 启动时的根文件夹都视为已同步过
      init(rootFolderIDs: Set<UUID>)

      /// 用户要求把该根文件夹添加到 Dock
      mutating func request(folderID: UUID)

      /// 搁置新建的根文件夹：名称定下来之前不添加 tile
      mutating func hold(folderID: UUID)

      /// 解除搁置，返回它此前是否在搁置中；此后的同步把它当作新出现的根文件夹
      @discardableResult
      mutating func release(folderID: UUID) -> Bool

      /// 重启后的 Dock 已读到期望的偏好：此刻偏好里已有 tile 的根文件夹确认加上，不再待添加
      mutating func recordDockRelaunch(onDockFolderIDs: Set<UUID>)

      /// 本次同步要添加 tile 的根文件夹：待添加的与新出现的，去掉已在 Dock 上的、已不是根文件夹的与搁置中的；
      /// 返回的集合就是同步之后仍待添加的集合
      mutating func folderIDsToAdd(
          rootFolderIDs: Set<UUID>,
          onDockFolderIDs: Set<UUID>
      ) -> Set<UUID>

      /// 被用户拖出 Dock 的根文件夹：tile 不在 Dock 上，下一次同步也不会添加；
      /// 新出现的、搁置中的与待添加的都不算，它们的 tile 只是还没加上
      func removedFolderIDs(
          rootFolderIDs: Set<UUID>,
          onDockFolderIDs: Set<UUID>
      ) -> Set<UUID>
  }
  ```

- 其余同步逻辑不变：stub 照常生成与更新（tile 不在 Dock 上的根文件夹也保留 stub，重新添加时直接引用）；已有 tile 的名称、位置与图标照常更新；多余的 tile 与 stub 照常删除。
- 每次同步结束后发出 `DockTileSynchronizer.didSynchronizeNotification`（`object` 为同步器），设置窗口据此刷新状态。
- Dock 偏好里的 tile 变化时发出 `DockTileSynchronizer.dockTilesDidChangeNotification`（`object` 为同步器），不触发同步：用户把 tile 拖出 Dock 后，实测 Dock 约 4.1 秒才把删除写进偏好，设置窗口据此立即刷新状态（观察方式见 02 的 `observeTiles(_:)`）。

### 查询与请求

`DockTileSynchronizer` 提供：

- `func rootFolderIDsRemovedFromDock() -> Set<UUID>`：被用户拖出 Dock 的根文件夹，即 `removedFolderIDs` 对当前根文件夹与 Dock 上现有 tile（`DockPreferences.folderIDs(ofTilesIn:)` 对 stub 目录的结果）的判定；刚新建、还没同步的根文件夹，搁置中的与已经要求添加的都不算
- `func addTile(for folderID: UUID)`：把该根文件夹记为待添加，并安排一次同步
- `func holdTile(for folderID: UUID)`：搁置新建的根文件夹
- `func releaseTile(for folderID: UUID)`：解除搁置；它此前在搁置中时安排一次同步

### 设置窗口

- 文件夹树里，tile 不在 Dock 上的根文件夹这一行，在名称右侧显示状态文字 “不在 Dock 上”：次要文字颜色（`secondaryLabelColor`）、小号系统字体；在 Dock 上的根文件夹、子文件夹与 App 都不显示。
- 底部按钮行新增 “添加到 Dock”，排在 “添加…”（见 09）之后；只有选中的是 tile 不在 Dock 上的根文件夹时可用，点击后调用 `addTile(for:)`。
- 文件夹树每次重建或刷新状态时读取一次 `rootFolderIDsRemovedFromDock()`，行的状态与按钮的可用状态都用这一次读取的结果；点击 “添加到 Dock” 后立即刷新一次，状态文字随即消失。
- `FolderStore.didChangeNotification` 时重建整棵树。
  - `DockTileSynchronizer.didSynchronizeNotification`、`DockTileSynchronizer.dockTilesDidChangeNotification` 与设置窗口成为 key window 时只原地刷新已显示各行的状态与按钮的可用状态，不重建
    - 新建根文件夹后立即进入重命名，随后的同步与 Dock 偏好里 tile 的变化都会发出通知；实测 view-based `NSOutlineView` 在编辑中 `reloadData` 会结束编辑，并把输入到一半的名称提交出去
  - 设置窗口成为 key window 时另按书签更新 App 与文件的位置，有变化才重建（见 07、08）
- “新建文件夹” 新建根文件夹时，先加入数据源再立即 `holdTile(for:)`（同步器收到变更通知后要等防抖间隔才同步，搁置赶得上）；名称编辑结束（`controlTextDidEndEditing`）时写回名称并 `releaseTile(for:)`
  - 按 Esc 取消编辑时名称保持原样，同样 `releaseTile(for:)`：实测 outline view 取消编辑时不发 `controlTextDidEndEditing`，在 `control(_:textView:doCommandBy:)` 收到 `cancelOperation(_:)` 时解除搁置，返回 false，取消编辑仍交给 outline view
- `SettingsWindowController` 与 `FolderTreeViewController` 通过构造函数拿到同步器，由 `AppDelegate` 传入。Dock 集成不可用（没有 stub 可执行文件，或读不到 Dock 偏好）时同步器为 nil：不显示状态，“添加到 Dock” 隐藏。

## 把 App 拖到 tile 上加入文件夹（需求 11）

### stub 声明可接收 App

- stub 的 Info.plist 增加 `CFBundleDocumentTypes`，其中接收 App 的一项：
  - `CFBundleTypeName = Application`
  - `CFBundleTypeRole = Viewer`
  - `LSHandlerRank = Alternate`
  - `LSItemContentTypes = [com.apple.application, com.apple.application-bundle]`
  - 取自 [macos-dock-folders](https://github.com/wjvalue/macos-dock-folders)（MIT）：从访达把 App 拖到 Dock 上的 tile 时，tile 高亮为放置目标，松手后 Launch Services 以 “打开文档” 的方式启动 stub；`Alternate` 让 stub 不成为 App 的默认打开方式
  - 接收文件的另一项见 06（需求 14）
- stub 改写后除 `codesign` 外再执行 `lsregister -f <bundle>`（`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`），Launch Services 才知道它接收的文档类型。
- Dock 上的 tile 之间不能互相拖放：拖动 Dock 图标时整个过程由 Dock 接管，只能排序或拖出。来源只能是访达等其它 App。

### stub 的行为

- stub 基于 `NSApplication` 运行，是 `LSUIElement` + `LSBackgroundOnly` 的后台 App，不激活任何 App：
  - 由点击 tile 启动：打开 `flotilla://folder/<id>`，与 02 一致
  - 由拖放启动：AppKit 在 `applicationDidFinishLaunching` 之前经 `application(_:open:)` 送来被拖的 URL，收齐后在 `applicationDidFinishLaunching` 里打开 `flotilla://folder/<id>/items?path=<路径>&path=<路径>`：每个被拖的项一个 `path` 查询项，取值为它的 POSIX 路径，由 `URLComponents` 编码
  - 其余不变：`activates = false`，等到回调（最多 5 秒）后退出；缺少 id 或打开失败时记日志并以非零状态退出
- 同一次拖放的事件可能被系统重复送达（参考项目实测）；stub 每次启动只发一个 URL，重复到达的 URL 由 Flotilla 侧 `addItems` 的去重吸收。

### Flotilla 侧

- 新类型 `Dock/DockTileRequest.swift`：stub 通过 URL 向 Flotilla 发出的请求

  ```swift
  enum DockTileRequest: Equatable {
      /// 展开或收起根文件夹的面板
      case toggleFolder(UUID)

      /// 把拖到 tile 上的这些项加入根文件夹
      case addItems(folderID: UUID, fileURLs: [URL])

      init?(url: URL)
  }
  ```

  - `flotilla://folder/<uuid>` → `.toggleFolder`
  - `flotilla://folder/<uuid>/items?path=…&path=…` → `.addItems`：`path` 解码后用 `URL(filePath:)` 还原，stub 送来的文件包、App 与文件夹路径以 `/` 结尾，还原成目录 URL；顺序与查询项一致；没有任何 `path` 时视为无法识别
  - 其它 URL 一律为 nil
- `AppDelegate.application(_:open:)`：`.toggleFolder` 交给 `DockFolderPresenter`；`.addItems` 先确认 id 是根文件夹（stub 只代表根文件夹，其它 id 一律忽略），再经 `FolderItem(url:title:)` 分类后交给 `FolderStore.shared.addItems(_:to:)`（见 06）；整个过程不激活 Flotilla。
  - App bundle 的判断在 `AppReference.isApplicationBundle(_ url: URL) -> Bool`，由 `FolderItem(url:title:)` 分类时调用
- 加入之后，文件夹树、tile 图标与面板都按既有的变更通知更新，不另加提示。

## 界面本地化（需求 12）

- 支持英文、简体中文、繁体中文、日文、韩文，跟随系统语言与 “系统设置 › 通用 › 语言与地区 › 应用程序” 里对 Flotilla 的单独设置；其它语言回落到英文。
- 资源：`Sources/Flotilla/Resources/<语言>.lproj/Localizable.strings`，语言目录为 `en`、`zh-Hans`、`zh-Hant`、`ja`、`ko`。
  - `Package.swift` 把 `Resources` 从编译中排除；`Scripts/bundle.sh` 把五个 `.lproj` 拷入 `Flotilla.app/Contents/Resources/`
  - `Info.plist` 增加 `CFBundleDevelopmentRegion = en`
- 代码里所有用户可见的文字用 `String(localized:comment:)`，键见下表；日志、`#warning` 与注释用中文，不本地化。
- 五张表的键完全一致，缺一个都不行：进程只选一种语言，缺键时显示的是键名而不是英文。
- 用词对照系统自带 App 在各语言下的同名功能（“设置…” “退出” “撤销” “拷貝” “取り消す” “오려두기” 等）。

| 键 | en | zh-Hans | zh-Hant | ja | ko |
|---|---|---|---|---|---|
| `mainMenu.quit` | Quit Flotilla | 退出归帆 | 結束歸帆 | 帰帆を終了 | Flotilla 종료 |
| `mainMenu.edit` | Edit | 编辑 | 編輯 | 編集 | 편집 |
| `mainMenu.undo` | Undo | 撤销 | 還原 | 取り消す | 실행 취소 |
| `mainMenu.redo` | Redo | 重做 | 重做 | やり直す | 실행 복귀 |
| `mainMenu.cut` | Cut | 剪切 | 剪下 | カット | 오려두기 |
| `mainMenu.copy` | Copy | 复制 | 拷貝 | コピー | 복사하기 |
| `mainMenu.paste` | Paste | 粘贴 | 貼上 | ペースト | 붙이기 |
| `mainMenu.selectAll` | Select All | 全选 | 全選 | すべてを選択 | 전체 선택 |
| `statusBar.settings` | Settings… | 设置… | 設定… | 設定… | 설정… |
| `settings.windowTitle` | Flotilla Settings | 归帆设置 | 歸帆設定 | 帰帆の設定 | Flotilla 설정 |
| `folders.sectionTitle` | Folders | 文件夹 | 檔案夾 | フォルダ | 폴더 |
| `folders.newFolder` | New Folder | 新建文件夹 | 新增檔案夾 | 新規フォルダ | 새로운 폴더 |
| `folders.untitledFolder` | Untitled Folder | 未命名文件夹 | 未命名檔案夾 | 名称未設定フォルダ | 제목 없는 폴더 |
| `folders.add` | Add… | 添加… | 加入… | 追加… | 추가… |
| `folders.addApps` | Add Apps… | 添加 App… | 加入 App… | アプリを追加… | 앱 추가… |
| `folders.addFiles` | Add Files… | 添加文件… | 加入檔案… | ファイルを追加… | 파일 추가… |
| `folders.addWebPage` | Add Web Page… | 添加网页… | 加入網頁… | Webページを追加… | 웹 페이지 추가… |
| `folders.webPageAlert.message` | Add Web Page | 添加网页 | 加入網頁 | Webページを追加 | 웹 페이지 추가 |
| `folders.webPageAlert.informative` | Enter the address of the web page. | 输入网页的网址。 | 輸入網頁的網址。 | WebページのURLを入力してください。 | 웹 페이지의 주소를 입력하십시오. |
| `folders.webPageAlert.add` | Add | 添加 | 加入 | 追加 | 추가 |
| `folders.webPageAlert.cancel` | Cancel | 取消 | 取消 | キャンセル | 취소 |
| `folders.addToDock` | Add to Dock | 添加到 Dock | 加入 Dock | Dockに追加 | Dock에 추가 |
| `folders.notOnDock` | Not in Dock | 不在 Dock 上 | 不在 Dock 上 | Dockにありません | Dock에 없음 |
| `folders.remove` | Delete | 删除 | 刪除 | 削除 | 삭제 |
| `general.sectionTitle` | General | 通用 | 一般 | 一般 | 일반 |
| `general.previewIconCount` | Icons shown in folder icon: | 文件夹图标内显示的图标数量： | 檔案夾圖像內顯示的圖像數量： | フォルダアイコンに表示するアイコンの数： | 폴더 아이콘에 표시할 아이콘 수: |
| `general.finderFolders` | Finder folders: | 访达里的文件夹： | Finder 裡的檔案夾： | Finderのフォルダ： | Finder 폴더: |
| `general.showHiddenFiles` | Show hidden files | 显示隐藏文件 | 顯示隱藏檔案 | 不可視ファイルを表示 | 숨김 파일 보기 |
| `general.accessibility` | Accessibility permission: | 辅助功能权限： | 輔助使用權限： | アクセシビリティの権限： | 손쉬운 사용 권한: |
| `general.accessibilityGranted` | Granted | 已授权 | 已授權 | 許可済み | 허용됨 |
| `general.accessibilityNotGranted` | Not granted | 未授权 | 未授權 | 未許可 | 허용되지 않음 |
| `general.openSystemSettings` | Open System Settings | 打开系统设置 | 打開系統設定 | システム設定を開く | 시스템 설정 열기 |
| `panel.back` | Back | 返回 | 返回 | 戻る | 뒤로 |
| `panel.openInFinder` | Open in Finder | 在访达中打开 | 在Finder裡打開 | Finderで開く | Finder에서 열기 |

- `panel.back` 是面板返回按钮的辅助功能标签；状态栏图标的辅助功能描述是 App 名，简繁中文为 “归帆” “歸帆”，日文为 “帰帆”，其它语言为 “Flotilla”。
- `panel.openInFinder` 照抄 Dock 自己的 `SHOW_IN_FINDER`，照原生原样不加中英文之间的空格（见 08）。

## 设置窗口的文件夹图标（需求 13）

- 文件夹树里文件夹行的图标是系统的通用文件夹图标（`NSWorkspace.shared.icon(for: .folder)`），根文件夹与子文件夹相同，不随预览数量与系统外观变化。
- App 行用 `AppReference.icon`。
- 需求 2 的预览图标与外观跟随只影响 Dock 上的 tile 与面板里的子文件夹。

## 单元测试

- `DockTileAdditionTracker`：
  - 启动时缺少 tile 的根文件夹不添加
  - 新出现的根文件夹添加
  - 还没确认新 Dock 读到的 tile 不在 Dock 上时不算被拖出、下一次同步再加
  - 新 Dock 读到之后、下一次同步之前被拖出的不再添加
  - 新 Dock 只读到部分 tile 时只确认读到的
  - 同步看到之后再消失不再添加
  - 用户请求的添加
  - 搁置期间不添加也不算被拖出，解除后添加
  - 只有搁置过的才报告解除
  - 搁置期间被删除的不添加
  - 待添加的被删除或不再是根文件夹时不添加
  - 被拖出的判定只包含启动时就缺 tile 的与确认加上之后又消失的，新出现的、待添加的与已要求添加的都不算
- `DockTileRequest`：两种 URL 的解析，`path` 里的空格与中文，多个 `path` 保持顺序；scheme、host、层级、id 不符或没有 `path` 的 URL 一律为 nil
- stub 的 Info.plist 含上述 `CFBundleDocumentTypes`
- 本地化：五张 `Localizable.strings` 都能解析、键集合完全相同、没有空值；代码里 `String(localized:` 引用的每个键都在表里，表里的每个键都被代码引用

## 验收

- `mise run swift:lint`、`swift test`、`mise run bundle` 全部通过；`build/Flotilla.app/Contents/Resources/` 下有五个 `.lproj`
- 真实 Dock 上：
  - 把 tile 拖出 Dock 后，Flotilla 不加回；设置窗口里该根文件夹显示 “不在 Dock 上”，选中后 “添加到 Dock” 可用，点击后 tile 回到 Dock、状态消失
  - 新建根文件夹仍自动出现在 Dock 上；重启 Flotilla 后被拖出的 tile 仍不加回
  - 从访达把一个或多个 App 拖到 tile 上：tile 高亮，松手后 App 出现在该文件夹里；前台 App 保持前台；拖文件与访达里的文件夹的结果见 06、07
  - 系统语言或 Flotilla 的单独语言设置切到五种语言之一时，菜单、设置窗口与面板返回按钮的辅助功能标签都换成对应语言；其它语言显示英文
  - 设置窗口里文件夹行显示系统文件夹图标，切换外观不重绘
