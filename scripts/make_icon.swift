// Renders Resources/AppIcon.icns: a night-blue rounded square with a snowflake and a drift.
//
// Usage: swift scripts/make_icon.swift   (writes Resources/AppIcon.icns via iconutil)
import AppKit

let outputDir = URL(fileURLWithPath: "Resources")
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Sugrob-\(ProcessInfo.processInfo.processIdentifier).iconset")

/// Draws the icon into a square context of `side` pixels.
func draw(side: CGFloat, in ctx: CGContext) {
    let s = side / 1024
    // Apple's icon grid: 824 pt rounded square centred in 1024, corner radius ~185.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185 * s, cornerHeight: 185 * s, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(CGColor(red: 0.06, green: 0.10, blue: 0.22, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()

    // Night sky gradient.
    let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 0.20, green: 0.33, blue: 0.62, alpha: 1),
        CGColor(red: 0.05, green: 0.09, blue: 0.22, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: tile.minY),
                           end: CGPoint(x: 0, y: tile.maxY), options: [])

    // A few small background flakes.
    let dots: [(CGFloat, CGFloat, CGFloat)] = [
        (230, 800, 9), (330, 700, 6), (780, 820, 8), (840, 660, 6), (200, 560, 7),
        (720, 520, 5), (450, 850, 6), (620, 760, 5), (880, 480, 7), (290, 420, 5),
    ]
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
    for (x, y, r) in dots {
        ctx.fillEllipse(in: CGRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s))
    }

    // The drift: a lumpy white hill along the bottom.
    let drift = CGMutablePath()
    drift.move(to: CGPoint(x: tile.minX, y: tile.minY))
    drift.addLine(to: CGPoint(x: tile.minX, y: 300 * s))
    drift.addCurve(to: CGPoint(x: 420 * s, y: 330 * s),
                   control1: CGPoint(x: 200 * s, y: 360 * s), control2: CGPoint(x: 320 * s, y: 350 * s))
    drift.addCurve(to: CGPoint(x: 700 * s, y: 290 * s),
                   control1: CGPoint(x: 540 * s, y: 305 * s), control2: CGPoint(x: 600 * s, y: 270 * s))
    drift.addCurve(to: CGPoint(x: tile.maxX, y: 340 * s),
                   control1: CGPoint(x: 800 * s, y: 310 * s), control2: CGPoint(x: 880 * s, y: 350 * s))
    drift.addLine(to: CGPoint(x: tile.maxX, y: tile.minY))
    drift.closeSubpath()
    let snow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 1),
        CGColor(red: 0.84, green: 0.89, blue: 0.97, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.saveGState()
    ctx.addPath(drift)
    ctx.clip()
    ctx.drawLinearGradient(snow, start: CGPoint(x: 0, y: 360 * s),
                           end: CGPoint(x: 0, y: tile.minY), options: [])
    ctx.restoreGState()

    // The snowflake: six arms with two pairs of branches each.
    let center = CGPoint(x: 512 * s, y: 590 * s)
    let arm = 230 * s
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(30 * s)
    ctx.setLineCap(.round)
    for i in 0..<6 {
        let angle = CGFloat(i) * .pi / 3 + .pi / 2
        let dir = CGPoint(x: cos(angle), y: sin(angle))
        func point(_ t: CGFloat, _ side: CGFloat = 0) -> CGPoint {
            CGPoint(x: center.x + dir.x * t - dir.y * side, y: center.y + dir.y * t + dir.x * side)
        }
        ctx.move(to: center)
        ctx.addLine(to: point(arm))
        for (t, len) in [(0.45, 0.30), (0.72, 0.22)] as [(CGFloat, CGFloat)] {
            let base = arm * t
            let l = arm * len
            ctx.move(to: point(base))
            ctx.addLine(to: point(base + l * 0.7, l * 0.7))
            ctx.move(to: point(base))
            ctx.addLine(to: point(base + l * 0.7, -l * 0.7))
        }
    }
    ctx.strokePath()
    ctx.restoreGState()
}

func png(side: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    draw(side: CGFloat(side), in: context.cgContext)
    context.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(side: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(side: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputDir.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { exit(1) }
print("Wrote Resources/AppIcon.icns")
