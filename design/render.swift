// Renders an SVG to a PNG at a given pixel size using AppKit (macOS 13+ reads SVG natively).
// Usage: swift render.swift <input.svg> <output.png> <pixels> [opaque]
import AppKit

let args = CommandLine.arguments
guard args.count >= 4, let px = Int(args[3]), px > 0 else {
    FileHandle.standardError.write(Data("usage: render.swift in.svg out.png pixels [opaque]\n".utf8))
    exit(2)
}
guard let image = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write(Data("cannot read \(args[1])\n".utf8))
    exit(1)
}
let opaque = args.count > 4 && args[4] == "opaque"
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
) else { exit(1) }
rep.size = NSSize(width: px, height: px)
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high
if opaque { NSColor.black.setFill(); NSRect(x: 0, y: 0, width: px, height: px).fill() }
image.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
