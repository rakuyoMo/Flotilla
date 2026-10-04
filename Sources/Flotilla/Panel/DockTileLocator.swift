import AppKit
import ApplicationServices
import os

// MARK: - DockTileLocator

/// 通过辅助功能（AX）读取 Dock 进程的 AX 树，定位根文件夹的 tile；无权限或找不到 tile 时退化为鼠标位置在 Dock 方向上的投影
///
/// AX 的坐标以主屏左上角为原点、y 向下，交给 AppKit 之前都要换算
@MainActor
final class DockTileLocator {
    /// AX 调用的超时（秒）：Dock 重启期间调用会失败，失败要快，不能长时间阻塞主线程
    private static let messagingTimeout: Float = 0.5

    /// Dock 偏好里记录 Dock 位置的键
    private static let orientationKey = "orientation"

    /// Dock 偏好里记录 tile 尺寸的键
    private static let tileSizeKey = "tilesize"

    /// Dock 偏好里没有 tile 尺寸时采用的值
    private static let defaultTileSize: CGFloat = 64

    /// Dock 区域在 tile 尺寸之外的厚度：tile 尺寸为 64 时，AX 实测 Dock 列表朝屏幕内侧的边距屏幕边缘 94 pt
    private static let dockAreaPadding: CGFloat = 30

    /// 带提示请求辅助功能权限的选项键，即 `kAXTrustedCheckOptionPrompt` 的取值
    private static let trustPromptOptionKey = "AXTrustedCheckOptionPrompt"

    /// 定位相关的日志
    private static let logger = Logger(
        subsystem: "com.rakuyo.flotilla",
        category: "DockTileLocator"
    )

    /// 从 AX 树里 tile 的 `AXURL`（指向 stub）解析出根文件夹 id
    private let builder: DockTileBundleBuilder

    /// 本次启动是否已经带提示地请求过辅助功能权限
    private var hasPromptedForTrust = false

    /// 创建定位器，并设置 AX 调用的全局超时
    /// - Parameter builder: 从 stub 位置解析根文件夹 id 的生成器
    init(builder: DockTileBundleBuilder) {
        self.builder = builder

        // 设在系统级元素上即为本进程所有 AX 调用的超时
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
    }
}

// MARK: - Locating

extension DockTileLocator {
    /// 定位根文件夹的 tile
    ///
    /// 第一次调用时带提示地请求辅助功能权限，每次启动最多提示一次；
    /// 没有权限、Dock 正在重启或找不到 tile 时，退化为鼠标位置在 Dock 方向上的投影
    /// - Returns: 没有任何屏幕时为 nil
    func locate(folderID: UUID) -> DockTileAnchor? {
        let edge = dockEdge()

        if
            requestTrustIfNeeded(),
            let tileFrame = tileFrame(of: folderID),
            let screen = Self.screen(
                containing: CGPoint(x: tileFrame.midX, y: tileFrame.midY)
            )
        {
            return DockTileAnchor(tileFrame: tileFrame, edge: edge, screen: screen)
        }

        Self.logger.notice(
            "未能通过辅助功能定位 tile，改用鼠标位置：\(folderID.uuidString, privacy: .public)"
        )

        return fallbackAnchor(edge: edge)
    }

    /// 快速路径：鼠标位置下的 Flotilla tile；没有权限或不在任何 Flotilla tile 上时返回 nil
    /// - Parameters:
    ///   - point: AppKit 屏幕坐标
    ///   - folderIDs: 候选的根文件夹
    func folderID(at point: CGPoint, among folderIDs: [UUID]) -> UUID? {
        guard
            AXIsProcessTrusted(),
            let dockElement = Self.dockApplicationElement(),
            let primaryScreenHeight = Self.primaryScreenHeight()
        else {
            return nil
        }

        let axPoint = Self.topLeftPoint(
            fromAppKitPoint: point,
            primaryScreenHeight: primaryScreenHeight
        )

        var element: AXUIElement? = nil
        let error = AXUIElementCopyElementAtPosition(
            dockElement,
            Float(axPoint.x),
            Float(axPoint.y),
            &element
        )

        guard
            error == .success,
            let element,
            let url = Self.url(of: element),
            let folderID = builder.folderID(forBundleURL: url)
        else {
            return nil
        }

        return folderIDs.contains(folderID) ? folderID : nil
    }

    /// 一次点击是否落在 Dock 区域，按 `dockArea(in:edge:tileSize:)` 估算
    /// - Parameter point: AppKit 屏幕坐标
    func isInDockArea(_ point: CGPoint) -> Bool {
        guard let screen = Self.screen(containing: point) else { return false }

        let dockArea = Self.dockArea(
            in: screen.frame,
            edge: dockEdge(),
            tileSize: dockTileSize()
        )

        return dockArea.contains(point)
    }
}

// MARK: - Geometry

extension DockTileLocator {
    /// 把以主屏左上角为原点、y 向下的矩形换算为 AppKit 屏幕坐标（以主屏左下角为原点、y 向上）
    static func appKitRect(
        fromTopLeftRect rect: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// 把 AppKit 屏幕坐标的点换算为以主屏左上角为原点、y 向下的点
    static func topLeftPoint(
        fromAppKitPoint point: CGPoint,
        primaryScreenHeight: CGFloat
    ) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    /// 估算的 Dock 区域：沿 Dock 所贴的屏幕边、厚度为 tile 尺寸加 `dockAreaPadding` 的条带
    ///
    /// Dock 进程在 Dock 层级只有一个铺满整个屏幕的窗口，窗口几何代表不了 Dock 区域；无权限时读不到 AX，只能按 Dock 偏好估算
    /// - Parameters:
    ///   - screenFrame: Dock 所在屏幕的 frame
    ///   - edge: Dock 所贴的屏幕边
    ///   - tileSize: Dock 偏好里的 tile 尺寸
    static func dockArea(
        in screenFrame: CGRect,
        edge: DockEdge,
        tileSize: CGFloat
    ) -> CGRect {
        screenFrame.divided(atDistance: tileSize + dockAreaPadding, from: edge.rectEdge).slice
    }

    /// 退化锚点：鼠标位置在 Dock 方向上的投影，落在 Dock 朝向屏幕内侧的那条边上
    /// - Parameters:
    ///   - point: 鼠标位置
    ///   - dockArea: Dock 占据的区域
    ///   - edge: Dock 所贴的屏幕边
    static func projection(
        of point: CGPoint,
        onto dockArea: CGRect,
        edge: DockEdge
    ) -> CGPoint {
        switch edge {
        case .bottom:
            CGPoint(x: point.x, y: dockArea.maxY)

        case .left:
            CGPoint(x: dockArea.maxX, y: point.y)

        case .right:
            CGPoint(x: dockArea.minX, y: point.y)
        }
    }
}

// MARK: - Private

extension DockTileLocator {
    /// Dock 所贴的屏幕边，取自 Dock 偏好
    private func dockEdge() -> DockEdge {
        let defaults = UserDefaults(suiteName: DockPreferences.dockDomain)

        return DockEdge(orientation: defaults?.string(forKey: Self.orientationKey))
    }

    /// Dock 的 tile 尺寸，取自 Dock 偏好
    private func dockTileSize() -> CGFloat {
        let defaults = UserDefaults(suiteName: DockPreferences.dockDomain)
        let tileSize = defaults?.object(forKey: Self.tileSizeKey) as? Double

        return tileSize.map { CGFloat($0) } ?? Self.defaultTileSize
    }

    /// 已有权限时直接返回 true；否则第一次调用时带提示地请求，之后只查询不提示
    private func requestTrustIfNeeded() -> Bool {
        guard !hasPromptedForTrust else { return AXIsProcessTrusted() }

        hasPromptedForTrust = true

        let options = [Self.trustPromptOptionKey: true] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }

    /// 在 Dock 的 AX 树里查找 `AXURL` 指向该根文件夹 stub 的 tile，返回它的 AppKit 屏幕坐标
    ///
    /// Dock 应用元素的子元素是 tile 列表，列表的子元素才是各个 tile；
    /// 开启自动隐藏时，Dock 重启后到第一次显示之前，所有 tile 的 frame 都是宽度为 0 的无效值，视同找不到
    private func tileFrame(of folderID: UUID) -> CGRect? {
        guard
            let dockElement = Self.dockApplicationElement(),
            let primaryScreenHeight = Self.primaryScreenHeight()
        else {
            return nil
        }

        let tiles = Self.children(of: dockElement).flatMap { Self.children(of: $0) }

        let tile = tiles.first {
            Self.url(of: $0).flatMap { builder.folderID(forBundleURL: $0) } == folderID
        }

        guard
            let tile,
            let frame = Self.frame(of: tile),
            !frame.isEmpty
        else {
            return nil
        }

        return Self.appKitRect(
            fromTopLeftRect: frame,
            primaryScreenHeight: primaryScreenHeight
        )
    }

    /// 退化锚点：鼠标所在屏幕（不在任何屏幕上时取 `NSScreen.main` 或第一块屏）上，
    /// 鼠标位置在估算的 Dock 区域上的投影，表示为宽高为 0 的 tile frame；
    /// 没有任何屏幕时为 nil
    private func fallbackAnchor(edge: DockEdge) -> DockTileAnchor? {
        let mouseLocation = NSEvent.mouseLocation
        let screen = Self.screen(containing: mouseLocation)
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return nil }

        let dockArea = Self.dockArea(in: screen.frame, edge: edge, tileSize: dockTileSize())
        let point = Self.projection(of: mouseLocation, onto: dockArea, edge: edge)

        return DockTileAnchor(
            tileFrame: CGRect(origin: point, size: .zero),
            edge: edge,
            screen: screen
        )
    }
}

// MARK: - Helpers

extension DockTileLocator {
    /// 包含该点的屏幕；点不在任何屏幕上时为 nil
    private static func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// 主屏（带菜单栏的屏幕）的高度，AX 的坐标以它的左上角为原点
    private static func primaryScreenHeight() -> CGFloat? {
        NSScreen.screens.first?.frame.height
    }

    /// Dock 进程的 AX 应用元素；每次重新创建，Dock 重启后不会拿着失效的元素；Dock 重启期间可能暂时没有
    private static func dockApplicationElement() -> AXUIElement? {
        NSRunningApplication
            .runningApplications(withBundleIdentifier: DockPreferences.dockDomain)
            .first
            .map { AXUIElementCreateApplication($0.processIdentifier) }
    }
}

// MARK: - Accessibility Attributes

extension DockTileLocator {
    /// 元素的子元素；读取失败时为空
    private static func children(of element: AXUIElement) -> [AXUIElement] {
        attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? []
    }

    /// 元素的 `AXURL`；Dock 的 App 与文件 tile 用它指向磁盘上的 App 或文件
    private static func url(of element: AXUIElement) -> URL? {
        attribute(kAXURLAttribute, of: element) as? URL
    }

    /// 元素的位置与尺寸，以主屏左上角为原点、y 向下
    private static func frame(of element: AXUIElement) -> CGRect? {
        guard
            let origin = value(
                of: kAXPositionAttribute,
                in: element,
                type: .cgPoint,
                initial: CGPoint.zero
            ),
            let size = value(
                of: kAXSizeAttribute,
                in: element,
                type: .cgSize,
                initial: CGSize.zero
            )
        else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    /// 读取以 `AXValue` 包装的几何属性；
    /// 读不到、不是 `AXValue` 或类型与 `type` 不符时为 nil
    /// - Parameters:
    ///   - type: 属性值的 `AXValueType`
    ///   - initial: 承接结果的初值，类型须与 `type` 对应
    private static func value<Value: BitwiseCopyable>(
        of attributeName: String,
        in element: AXUIElement,
        type: AXValueType,
        initial: Value
    ) -> Value? {
        guard
            let rawValue = attribute(attributeName, of: element),
            CFGetTypeID(rawValue) == AXValueGetTypeID()
        else {
            return nil
        }

        var result = initial
        let axValue = unsafeDowncast(rawValue, to: AXValue.self)

        guard AXValueGetValue(axValue, type, &result) else { return nil }

        return result
    }

    /// 读取元素的一个属性；元素失效、超时或没有该属性时为 nil
    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef? = nil
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)

        guard error == .success else { return nil }

        return value
    }
}
