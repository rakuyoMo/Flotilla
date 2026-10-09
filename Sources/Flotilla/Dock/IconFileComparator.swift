import CoreGraphics
import Foundation
import ImageIO

// MARK: - IconFileComparator

/// 按解码后的像素比对两份 `.icns`，判断 stub 的图标是否需要改写
///
/// 预览里的 App 图标由 IconServices 渲染并缓存在系统里，缓存重新生成后，同一图标、同一尺寸的像素会差一两级；
/// 逐字节比对会把这种差别当成图标变了，改写 stub、让 Dock 无谓地重启
enum IconFileComparator {
    /// 视为同一个图标时，对应像素的每个分量（8 位、预乘）最多允许相差的级数
    ///
    /// 取值是 macOS 27 上实测的上限：
    /// - 16 个 App 在浅色、深色外观下各自占满四格，图标源逐字节相同、IconServices 缓存不同代时，组图标最多差 3 级
    /// - 系统把一批 App 图标的缓存整体换代前后，同一个组图标最多差 4 级
    static let componentTolerance = 4

    /// 两份 `.icns` 是否画出同一个图标
    ///
    /// 字节相同时为 true；否则逐张比较解出的图像：张数与各张尺寸都相同、
    /// 对应像素的每个分量相差都不超过 `componentTolerance` 时为 true，任一份解不出图像时为 false
    static func isEquivalent(_ lhs: Data, _ rhs: Data) -> Bool {
        // 字节相同就是同一个图标，直接返回，省去解码
        guard lhs != rhs else { return true }

        guard
            let lhsImages = images(in: lhs),
            let rhsImages = images(in: rhs),
            lhsImages.count == rhsImages.count
        else {
            return false
        }

        return zip(lhsImages, rhsImages).allSatisfy {
            isEquivalent($0, $1)
        }
    }
}

// MARK: - Private

extension IconFileComparator {
    /// 两张图像尺寸相同，且对应像素的每个分量相差都不超过 `componentTolerance`
    private static func isEquivalent(_ lhs: CGImage, _ rhs: CGImage) -> Bool {
        guard
            lhs.width == rhs.width,
            lhs.height == rhs.height,
            let lhsComponents = premultipliedComponents(of: lhs),
            let rhsComponents = premultipliedComponents(of: rhs)
        else {
            return false
        }

        return lhsComponents.withUnsafeBufferPointer { lhsBuffer in
            rhsComponents.withUnsafeBufferPointer { rhsBuffer in
                for index in lhsBuffer.indices
                    where abs(Int(lhsBuffer[index]) - Int(rhsBuffer[index])) > componentTolerance
                {
                    return false
                }

                return true
            }
        }
    }

    /// 用 ImageIO 解出 `.icns` 里的全部图像；解不出或一张都没有时为 nil
    private static func images(in data: Data) -> [CGImage]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let count = CGImageSourceGetCount(source)
        let images = (0 ..< count).compactMap {
            CGImageSourceCreateImageAtIndex(source, $0, nil)
        }

        guard count > 0, images.count == count else { return nil }

        return images
    }

    /// 把图像画进 8 位 sRGB、预乘 alpha 的位图，依次给出各像素的 RGBA 分量；建不出位图时为 nil
    ///
    /// 两份图标走同一种转换，格式不同的条目也能比较；
    /// 用预乘的值比较：几乎透明的像素反预乘后，1 级的差会被放大成几十级
    private static func premultipliedComponents(of image: CGImage) -> [UInt8]? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let bytesPerRow = image.width * 4
        var components = [UInt8](repeating: 0, count: bytesPerRow * image.height)

        let isDrawn = components.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }

            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
            )

            return true
        }

        return isDrawn ? components : nil
    }
}
