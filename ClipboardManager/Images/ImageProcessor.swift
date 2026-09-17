import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ProcessedImage {
    var data: Data
    var fileExtension: String
    var uti: String
    var width: Int
    var height: Int
    var thumbnail: Data
    var thumbnailExtension: String
}

/// Normalizes captured image data: downscales anything over `maxImageEdge`, re-encodes as JPEG (opaque)
/// or PNG (has real transparency), and produces a small thumbnail for the cards.
enum ImageProcessor {
    static func process(_ raw: Data) -> ProcessedImage? {
        guard let source = CGImageSourceCreateWithData(raw as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }

        let transparent = hasTransparentPixels(original)
        let full = downscale(original, maxEdge: AppConfig.maxImageEdge)
        let thumb = downscale(original, maxEdge: AppConfig.thumbnailEdge)

        guard let fullData = encode(full, png: transparent),
              let thumbData = encode(thumb, png: transparent) else {
            return nil
        }

        return ProcessedImage(
            data: fullData,
            fileExtension: transparent ? "png" : "jpg",
            uti: transparent ? UTType.png.identifier : UTType.jpeg.identifier,
            width: full.width,
            height: full.height,
            thumbnail: thumbData,
            thumbnailExtension: transparent ? "png" : "jpg"
        )
    }

    static func dimensions(of data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (w, h)
    }

    // MARK: - Steps

    /// True only if the image both declares an alpha channel and actually contains a non-opaque pixel
    /// (sampled from a ≤64px rendering, which is cheap and catches real transparency).
    static func hasTransparentPixels(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        default:
            break
        }
        let scale = min(1, 64 / CGFloat(max(image.width, image.height, 1)))
        let width = max(1, Int(CGFloat(image.width) * scale))
        let height = max(1, Int(CGFloat(image.height) * scale))
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return false }
        var index = 3
        while index < pixels.count {
            if pixels[index] < 250 { return true }
            index += 4
        }
        return false
    }

    static func downscale(_ image: CGImage, maxEdge: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    static func encode(_ image: CGImage, png: Bool) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: image.width, height: image.height)
        if png {
            return rep.representation(using: .png, properties: [:])
        }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: AppConfig.jpegQuality])
    }
}
