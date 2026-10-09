import AppKit

// MARK: - SolidColorIcon

/// 测试用的纯色图标：两份只差几级红色分量的图标，用来检验按像素比对 stub 图标时的容差
enum SolidColorIcon {
    /// 整幅填满同一颜色的 512 pt 图像
    ///
    /// 用设备 RGB 指定颜色：栅格化成 `.icns` 的位图也是设备 RGB，各分量原样写入
    /// - Parameter red: 红色分量，0–255；绿色、蓝色分量固定
    static func make(red: Int) -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: false) { canvas in
            NSColor(
                deviceRed: CGFloat(red) / 255,
                green: 128 / 255,
                blue: 64 / 255,
                alpha: 1
            ).setFill()

            canvas.fill()

            return true
        }
    }
}
