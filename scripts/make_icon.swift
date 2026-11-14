// Renders the app icon (a small sunburst) to a 1024px PNG. Usage: swift make_icon.swift out.png
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1).setFill()
NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()

let center = NSPoint(x: 512, y: 512)
// (inner radius, outer radius, wedge fractions)
let rings: [(CGFloat, CGFloat, [CGFloat])] = [
    (120, 200, [0.34, 0.24, 0.18, 0.14, 0.10]),
    (208, 280, [0.20, 0.12, 0.16, 0.06, 0.12, 0.05, 0.09]),
    (288, 345, [0.10, 0.07, 0.05, 0.11, 0.04, 0.06]),
]
for (ringIndex, ring) in rings.enumerated() {
    var angle: CGFloat = 90
    for fraction in ring.2 {
        let sweep = fraction * 360
        let hue = (90 - angle + sweep / 2) / 360
        NSColor(hue: hue.truncatingRemainder(dividingBy: 1), saturation: 0.68 - 0.06 * CGFloat(ringIndex),
                brightness: 0.96 - 0.07 * CGFloat(ringIndex), alpha: 1).setFill()
        let p = NSBezierPath()
        p.appendArc(withCenter: center, radius: ring.1, startAngle: angle, endAngle: angle - sweep + 1.6, clockwise: true)
        p.appendArc(withCenter: center, radius: ring.0, startAngle: angle - sweep + 1.6, endAngle: angle, clockwise: false)
        p.close()
        p.fill()
        angle -= sweep
    }
}
NSColor(white: 1, alpha: 0.92).setFill()
NSBezierPath(ovalIn: NSRect(x: 512 - 96, y: 512 - 96, width: 192, height: 192)).fill()

try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
