// Draws the app icon into an .iconset folder. Usage: swift make_icon.swift <out.iconset>
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(starting: NSColor(red: 0.20, green: 0.55, blue: 1.0, alpha: 1),
               ending: NSColor(red: 0.08, green: 0.25, blue: 0.70, alpha: 1))!.draw(in: path, angle: -90)

    let cfg = NSImage.SymbolConfiguration(pointSize: rect.width * 0.5, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let globe = NSImage(systemSymbolName: "network", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let g = globe.size
        globe.draw(in: NSRect(x: rect.midX - g.width / 2 - rect.width * 0.03, y: rect.midY - g.height / 2 + rect.width * 0.03,
                              width: g.width, height: g.height))
    }
    // Green "healthy" badge with a checkmark, kept inside the rounded square
    let d = rect.width * 0.30
    let badge = NSRect(x: rect.maxX - d - rect.width * 0.06, y: rect.minY + rect.width * 0.06, width: d, height: d)
    NSColor.white.setFill(); NSBezierPath(ovalIn: badge.insetBy(dx: -s * 0.014, dy: -s * 0.014)).fill()
    NSColor(red: 0.18, green: 0.78, blue: 0.35, alpha: 1).setFill(); NSBezierPath(ovalIn: badge).fill()
    let check = NSBezierPath()
    check.move(to: NSPoint(x: badge.minX + d * 0.27, y: badge.minY + d * 0.52))
    check.line(to: NSPoint(x: badge.minX + d * 0.44, y: badge.minY + d * 0.34))
    check.line(to: NSPoint(x: badge.minX + d * 0.74, y: badge.minY + d * 0.68))
    check.lineWidth = d * 0.11
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor.white.setStroke(); check.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
