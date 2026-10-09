import AppKit
import os

// MARK: - DockGroupPresenter

/// 面板的展开、收起与切换，是 `flotilla://folder/<id>` URL 事件的最终接收者
///
/// 点击 tile 有两条路径：有辅助功能权限时，全局鼠标监听配合 AX 命中测试直接识别（快速路径）；
/// 无论有无权限，stub 都会打开 URL（URL 路径）。
/// 两路信号与面板以外的点击都交给 `DockGroupPresenterState` 归并
@MainActor
final class DockGroupPresenter: NSObject {
    /// 面板相关的日志
    private static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "DockGroupPresenter"
    )

    /// 文件夹树的唯一数据源
    private let store: GroupStore

    /// 定位 tile，并为快速路径做命中测试
    private let locator: DockTileLocator

    /// 全局唯一的面板
    private let panelController: GroupPanelController

    /// 展开状态与信号去重
    private var state = DockGroupPresenterState()

    /// 已安装的鼠标事件监听，保持引用以免被释放
    private var eventMonitors: [Any] = []

    /// 创建面板调度者
    /// - Parameters:
    ///   - store: 文件夹树的唯一数据源
    ///   - preferences: 用户设置，决定子文件夹图标里的预览数量
    ///   - locator: 定位 tile
    init(store: GroupStore, preferences: Preferences, locator: DockTileLocator) {
        self.store = store
        self.locator = locator
        panelController = GroupPanelController(store: store, preferences: preferences)

        super.init()

        panelController.dismissRequestHandler = { [weak self] in
            self?.dismiss()
        }
    }

    /// 开始监听鼠标点击、文件夹树与屏幕参数的变化
    func start() {
        installMouseMonitors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(groupStoreDidChange),
            name: GroupStore.didChangeNotification,
            object: store
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(dismiss),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// URL 路径：stub 打开 `flotilla://folder/<id>` 后由 `AppDelegate` 转交；不是根文件夹的 id 一律忽略
    func handleURLSignal(groupID: UUID) {
        guard store.rootGroups.contains(where: { $0.id == groupID }) else {
            Self.logger.notice("忽略不存在的根文件夹：\(groupID.uuidString, privacy: .public)")
            return
        }

        apply(state.receiveURL(groupID: groupID, time: Self.now))
    }
}

// MARK: - Event Handling

extension DockGroupPresenter {
    /// 收起面板：Esc、启动 App、打开文件或网页、屏幕参数变化、当前文件夹被删除等
    @objc
    private func dismiss() {
        apply(state.dismiss())
    }

    /// 文件夹树变化：展示中的文件夹仍在则重建网格并尽量保留当前层级，否则收起
    @objc
    private func groupStoreDidChange() {
        guard state.presentedGroupID != nil, !panelController.reload() else { return }

        dismiss()
    }

    /// 安装鼠标监听：全局监听收到发往其它 App（含 Dock、菜单栏）的点击，本地监听收到发往 Flotilla 自己窗口的点击
    private func installMouseMonitors() {
        let globalMask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .rightMouseDown,
            .otherMouseDown,
        ]

        let globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: globalMask
        ) { [weak self] event in
            self?.handleGlobalMouseEvent(event)
        }

        // 状态栏图标、设置窗口也是面板以外的位置；面板自己的点击交给面板处理
        let localMask: NSEvent.EventTypeMask = [
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ]

        let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: localMask
        ) { [weak self] event in
            self?.handleLocalMouseDown(event)

            return event
        }

        eventMonitors = [globalMonitor, localMonitor].compactMap(\.self)
    }

    /// 发往其它 App 的鼠标事件：左键按下时尝试识别 Flotilla 的 tile，其余按下都是面板以外的点击；
    /// 左键拖动与抬起交给状态判定拖动 tile 与长按
    private func handleGlobalMouseEvent(_ event: NSEvent) {
        let location = NSEvent.mouseLocation
        let time = Self.now

        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // 读访达里的文件夹期间的按下（例如点系统隐私授权框）排到读取结束后才处理到，
            // 既不算面板以外的点击，也不算点击 tile
            guard !panelController.readPeriods.contains(event.timestamp) else { return }

            // 按住 Control 或 Command 的左键点击由 Dock 弹出菜单或在访达中显示，不启动 stub，不算点击 tile
            let isPlainLeftClick = event.type == .leftMouseDown
                && event.modifierFlags.isDisjoint(with: [.control, .command])

            let tileID = isPlainLeftClick
                ? locator.groupID(at: location, among: store.rootGroups.map(\.id))
                : nil

            apply(state.mouseDown(
                onTile: tileID,
                at: location,
                isInDockArea: isInDockAreaWhilePresenting(location),
                time: time
            ))

        case .leftMouseDragged:
            apply(state.mouseDragged(to: location, time: time))

        case .leftMouseUp:
            apply(state.mouseUp(time: time))

        default:
            break
        }
    }

    /// 发往 Flotilla 自己窗口的按下：不在面板里的都按面板以外的点击处理
    private func handleLocalMouseDown(_ event: NSEvent) {
        guard event.window !== panelController.panel else { return }

        // 读访达里的文件夹期间的按下排到读取结束后才处理到，不算面板以外的点击
        guard !panelController.readPeriods.contains(event.timestamp) else { return }

        apply(state.mouseDown(
            onTile: nil,
            at: NSEvent.mouseLocation,
            isInDockArea: false,
            time: Self.now
        ))
    }
}

// MARK: - Private

extension DockGroupPresenter {
    /// 当前时间：系统启动以来的秒数，与信号合并的时间窗比较
    private static var now: TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    /// 把状态迁移落实到面板
    private func apply(_ transition: DockGroupPresenterTransition) {
        switch transition {
        case .unchanged:
            break

        case .expand(let groupID):
            expand(groupID)

        case .collapse:
            panelController.collapse()
        }
    }

    /// 定位 tile 并展开；Dock 正在重启等原因定位不到时由定位器退化到鼠标位置，连屏幕都没有时放弃并同步状态
    ///
    /// 展开之后按书签把这个根文件夹里的 App 与文件跟到新位置，有变化时经 `groupStoreDidChange` 重建网格
    private func expand(_ groupID: UUID) {
        guard
            let group = store.rootGroups.first(where: { $0.id == groupID }),
            let anchor = locator.locate(groupID: groupID)
        else {
            Self.logger.error("无法展开根文件夹：\(groupID.uuidString, privacy: .public)")
            dismiss()
            return
        }

        panelController.expand(rootGroup: group, anchor: anchor)

        // 推迟到下一轮主线程：展开不因解析书签而变慢，提交引起的重建也不会在展开途中重入 `apply`
        DispatchQueue.main.async { [weak self] in
            self?.store.updateItemLocations(in: groupID)
        }
    }

    /// 面板展开时判断点击是否落在 Dock 区域；未展开时不需要，省去一次读取 Dock 偏好
    private func isInDockAreaWhilePresenting(_ location: CGPoint) -> Bool {
        state.presentedGroupID != nil && locator.isInDockArea(location)
    }
}
