// Draws the Blackmold app icon and writes Resources/AppIcon.icns.
// Run from the project folder: swift Scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// macOS icon grid: an 824 pt rounded square centered on the canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the tile.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: NSColor.black.withAlphaComponent(0.45).cgColor)
context.addPath(tilePath)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath)
context.clip()

// Near-black body, a touch lighter at the top.
let body = CGGradient(colorsSpace: nil, colors: [
    NSColor(calibratedWhite: 0.11, alpha: 1).cgColor,
    NSColor(calibratedWhite: 0.02, alpha: 1).cgColor,
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(body, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// The mold: a soft moss-green glow spreading up from below the island.
let moss = CGGradient(colorsSpace: nil, colors: [
    NSColor(calibratedRed: 0.29, green: 0.62, blue: 0.34, alpha: 0.55).cgColor,
    NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.16, alpha: 0.18).cgColor,
    NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.0, alpha: 0).cgColor,
] as CFArray, locations: [0, 0.45, 1])!
context.drawRadialGradient(moss, startCenter: CGPoint(x: 512, y: 470), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 470), endRadius: 430, options: [])

// Thin highlight along the top edge.
context.addPath(tilePath)
context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.08).cgColor)
context.setLineWidth(6)
context.strokePath()

// The island: a black notch shape with a hairline rim.
let island = CGRect(x: 232, y: 560, width: 560, height: 168)
let islandPath = CGPath(roundedRect: island, cornerWidth: 84, cornerHeight: 84, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -10), blur: 40, color: NSColor.black.withAlphaComponent(0.8).cgColor)
context.addPath(islandPath)
context.setFillColor(NSColor.black.cgColor)
context.fillPath()
context.restoreGState()
context.addPath(islandPath)
context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.14).cgColor)
context.setLineWidth(3)
context.strokePath()

// Album cover on the left of the island.
let cover = CGRect(x: 292, y: 594, width: 100, height: 100)
context.saveGState()
context.addPath(CGPath(roundedRect: cover, cornerWidth: 24, cornerHeight: 24, transform: nil))
context.clip()
let art = CGGradient(colorsSpace: nil, colors: [
    NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.95, alpha: 1).cgColor,
    NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.86, alpha: 1).cgColor,
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(art, start: CGPoint(x: cover.minX, y: cover.maxY), end: CGPoint(x: cover.maxX, y: cover.minY), options: [])
context.restoreGState()

// Six spectrum bars on the right, moss green.
let levels: [CGFloat] = [0.55, 0.9, 0.7, 1.0, 0.6, 0.35]
for (index, level) in levels.enumerated() {
    let height = 26 + 74 * level
    let bar = CGRect(x: 560 + CGFloat(index) * 30, y: 644 - height / 2, width: 16, height: height)
    context.addPath(CGPath(roundedRect: bar, cornerWidth: 8, cornerHeight: 8, transform: nil))
    context.setFillColor(NSColor(calibratedRed: 0.45, green: 0.86, blue: 0.5, alpha: 0.95).cgColor)
    context.fillPath()
}

context.restoreGState()
image.unlockFocus()

// Write every size iconutil expects, then pack them.
let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Blackmold.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let base = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.cgContext.draw(base, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let output = URL(fileURLWithPath: "Resources/AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! process.run()
process.waitUntilExit()
try! rep1024(base).write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))
print(process.terminationStatus == 0 ? "wrote \(output.path)" : "iconutil failed")

func rep1024(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}
