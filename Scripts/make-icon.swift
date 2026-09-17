// Generates the AppIcon asset catalog: a clipboard glyph on a blue-violet gradient, macOS rounded-square shape.
//   swift Scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconSet = root.appendingPathComponent("ClipboardManager/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size, flipped: false) { rect in
        let s = rect.width
        // macOS icon grid: the shape occupies ~80% of the canvas.
        let inset = s * 0.1
        let square = rect.insetBy(dx: inset, dy: inset)
        let radius = square.width * 0.225
        let path = NSBezierPath(roundedRect: square, xRadius: radius, yRadius: radius)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = s * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor(calibratedRed: 0.25, green: 0.35, blue: 0.9, alpha: 1).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.36, green: 0.55, blue: 1.0, alpha: 1),
            NSColor(calibratedRed: 0.42, green: 0.27, blue: 0.86, alpha: 1),
        ])!
        gradient.draw(in: path, angle: -60)

        // Soft top highlight.
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let highlight = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
        highlight.draw(in: NSRect(x: square.minX, y: square.midY, width: square.width, height: square.height / 2), angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // Glyph.
        let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .medium)
        if let symbol = NSImage(systemSymbolName: "doc.on.clipboard.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let tinted = NSImage(size: symbol.size, flipped: false) { r in
                symbol.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            let glyphSize = tinted.size
            let origin = NSPoint(x: square.midX - glyphSize.width / 2, y: square.midY - glyphSize.height / 2)
            let glyphShadow = NSShadow()
            glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            glyphShadow.shadowBlurRadius = s * 0.015
            glyphShadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
            NSGraphicsContext.saveGraphicsState()
            glyphShadow.set()
            tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        return true
    }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(size: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
var rendered: [Int: Data] = [:]
for entry in entries {
    let pixels = entry.size * entry.scale
    let name = "icon_\(pixels).png"
    if rendered[pixels] == nil {
        rendered[pixels] = render(pixels)
        try rendered[pixels]!.write(to: iconSet.appendingPathComponent(name))
    }
    images.append(["size": "\(entry.size)x\(entry.size)", "idiom": "mac", "filename": name, "scale": "\(entry.scale)x"])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: iconSet.appendingPathComponent("Contents.json"))
try #"{"info":{"version":1,"author":"xcode"}}"#.write(to: root.appendingPathComponent("ClipboardManager/Assets.xcassets/Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(rendered.count) icon sizes to \(iconSet.path)")
