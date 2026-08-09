import AppKit
import Foundation

// Renders AppIcon.icns from code rather than checking in a binary blob, so the icon is
// reviewable, reproducible, and editable without a design tool.
//
//   swift Scripts/generate-icon.swift <output-directory>

let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build")

/// Apple's macOS icon grid: the artwork is inset from the canvas so that the shadow and the
/// neighbouring icons in the Dock have room to breathe.
let artworkInset: CGFloat = 0.098
/// The squircle radius Apple uses, as a fraction of the artwork's width.
let cornerRatio: CGFloat = 0.2237

let topColor = NSColor(srgbRed: 0.259, green: 0.647, blue: 0.961, alpha: 1)     // sky
let bottomColor = NSColor(srgbRed: 0.310, green: 0.275, blue: 0.898, alpha: 1)  // indigo

func symbolImage(pointSize: CGFloat) -> NSImage? {
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
    guard let base = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) else { return nil }
    // Tinted into its own transparent image first; compositing white over the canvas would wash out
    // the gradient behind it.
    let tinted = NSImage(size: base.size)
    tinted.lockFocus()
    base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    return tinted
}

func render(pixels: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let side = CGFloat(pixels)
    let inset = side * artworkInset
    let artwork = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let squircle = NSBezierPath(roundedRect: artwork,
                                xRadius: artwork.width * cornerRatio,
                                yRadius: artwork.width * cornerRatio)

    NSGradient(starting: bottomColor, ending: topColor)?.draw(in: squircle, angle: 90)

    // A hairline highlight along the top edge keeps the flat gradient from looking like a sticker.
    squircle.lineWidth = max(1, side * 0.004)
    NSColor.white.withAlphaComponent(0.18).setStroke()
    squircle.stroke()

    if let glyph = symbolImage(pointSize: side * 0.42) {
        let target = NSRect(
            x: artwork.midX - glyph.size.width / 2,
            y: artwork.midY - glyph.size.height / 2,
            width: glyph.size.width,
            height: glyph.size.height
        )
        glyph.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    } else {
        FileHandle.standardError.write(Data("warning: SF Symbol unavailable; icon has no glyph\n".utf8))
    }

    return rep
}

// (point size, scale) pairs an .iconset must contain for a complete .icns.
let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

let fileManager = FileManager.default
let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

for (points, scale) in variants {
    guard let rep = render(pixels: points * scale), let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("error: could not render \(points)@\(scale)x\n".utf8))
        exit(1)
    }
    let suffix = scale == 1 ? "" : "@\(scale)x"
    try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
}

let icns = outputDirectory.appendingPathComponent("AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["--convert", "icns", iconset.path, "--output", icns.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("error: iconutil failed\n".utf8))
    exit(1)
}

try? fileManager.removeItem(at: iconset)
print("Created \(icns.path)")
