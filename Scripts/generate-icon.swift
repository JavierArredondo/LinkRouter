import AppKit
import Foundation

// Rasterises Resources/AppIcon.svg into the assets the app bundle needs.
//
//   swift Scripts/generate-icon.swift <output-directory>
//
// Produces AppIcon.icns (bundle icon) and AppIcon.png (1024px). The SVG is the single source of
// truth — edit that, not this file, to change the artwork. macOS decodes SVG natively through
// NSImage, so the geometry does not have to be duplicated as drawing code here.
//
// The mark is original geometry rather than an SF Symbol: Apple's SF Symbols licence permits the
// symbols in an app's interface but not in its icon or logo. The menu-bar item still uses the real
// symbol, which is exactly the use the licence allows.

let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let svgURL = projectRoot.appendingPathComponent("Resources/AppIcon.svg")
let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : projectRoot.appendingPathComponent("build")

guard let artwork = NSImage(contentsOf: svgURL), artwork.size.width > 0 else {
    FileHandle.standardError.write(Data("error: could not read \(svgURL.path)\n".utf8))
    exit(1)
}

/// Apple's macOS icon grid insets the artwork within the canvas so the Dock shadow and neighbouring
/// icons have room. The SVG itself is full-bleed, which is what a README or a logo wants, so only
/// the bundle icon gets the inset.
let iconGridInset: CGFloat = 0.098

func render(pixels: Int, inset: CGFloat) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let side = CGFloat(pixels)
    let margin = side * inset
    artwork.draw(in: NSRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2),
                 from: .zero, operation: .sourceOver, fraction: 1)
    return rep
}

func png(_ rep: NSBitmapImageRep) -> Data? { rep.representation(using: .png, properties: [:]) }

let fileManager = FileManager.default
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

// (point size, scale) pairs an .iconset must contain for a complete .icns.
let variants: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
let iconset = outputDirectory.appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconset)
try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

for (points, scale) in variants {
    guard let rep = render(pixels: points * scale, inset: iconGridInset), let data = png(rep) else {
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

guard let full = render(pixels: 1024, inset: 0), let data = png(full) else { exit(1) }
let pngURL = outputDirectory.appendingPathComponent("AppIcon.png")
try data.write(to: pngURL)

print("Created \(icns.path)")
print("Created \(pngURL.path)")
