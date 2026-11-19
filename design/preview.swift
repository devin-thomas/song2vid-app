// Builds the preview sheet: the icon at 1024 (shown scaled), 128, 32 and 16 px on light and dark
// backgrounds, plus the small sizes enlarged with pixels kept hard.
// Usage: swift preview.swift <dir holding p1024.png p128.png p32.png p16.png> <output.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else { exit(2) }
let dir = args[1]

func load(_ px: Int) -> NSImage { NSImage(contentsOfFile: "\(dir)/p\(px).png")! }

let width = 1600, height = 700
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32
) else { exit(1) }
rep.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx

let light = NSColor(white: 0.96, alpha: 1)
let dark = NSColor(white: 0.11, alpha: 1)
light.setFill(); NSRect(x: 0, y: 0, width: width / 2, height: height).fill()
dark.setFill(); NSRect(x: width / 2, y: 0, width: width / 2, height: height).fill()

func draw(_ image: NSImage, at origin: CGPoint, size: CGFloat, pixelated: Bool = false) {
    ctx.imageInterpolation = pixelated ? .none : .high
    image.draw(in: NSRect(x: origin.x, y: origin.y, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1)
}

let panels: [(x: CGFloat, label: NSColor)] = [(0, .darkGray), (CGFloat(width / 2), .lightGray)]
for panel in panels {
    // Large icon, drawn at 480 px.
    draw(load(1024), at: CGPoint(x: panel.x + 160, y: 190), size: 480)
    // 128, 32 and 16 at true size along the bottom.
    draw(load(128), at: CGPoint(x: panel.x + 60, y: 30), size: 128)
    draw(load(32), at: CGPoint(x: panel.x + 230, y: 78), size: 32)
    draw(load(16), at: CGPoint(x: panel.x + 290, y: 86), size: 16)
    // The same small sizes enlarged four times with hard pixels, to judge legibility.
    draw(load(32), at: CGPoint(x: panel.x + 360, y: 30), size: 128, pixelated: true)
    draw(load(16), at: CGPoint(x: panel.x + 520, y: 30), size: 128, pixelated: true)
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
