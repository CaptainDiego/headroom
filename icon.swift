// Renders the app icon as a vector drawing into an .iconset folder.
// Flat colors and no 1024px variant keep the .icns small (~110 KB).
// Usage: swift icon.swift <out.iconset>   (build.sh runs this, then iconutil)
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Draws on a 1024×1024 canvas (y up), following the macOS icon grid.
func draw(_ c: CGContext) {
    // Background tile (824pt with ~185pt corners, centered), soft drop shadow.
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                      cornerWidth: 185, cornerHeight: 185, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.35))
    c.addPath(tile); c.setFillColor(rgb(0x1E1A18)); c.fillPath()
    c.restoreGState()
    c.addPath(tile); c.setFillColor(rgb(0x2A2421)); c.fillPath()

    // Gauge: 240° track, ~65% filled.
    let center = CGPoint(x: 512, y: 470), r: CGFloat = 255
    let start = CGFloat.pi * 7 / 6, sweep = CGFloat.pi * 4 / 3, fill: CGFloat = 0.65
    let end = start - sweep * fill
    c.setLineCap(.round)
    c.setLineWidth(74)
    c.addArc(center: center, radius: r, startAngle: start, endAngle: start - sweep, clockwise: true)
    c.setStrokeColor(rgb(0xFFFFFF, 0.10)); c.strokePath()

    // Filled portion of the arc.
    c.addArc(center: center, radius: r, startAngle: start, endAngle: end, clockwise: true)
    c.setStrokeColor(rgb(0xE3784C)); c.strokePath()

    // Needle pointing at the fill level, plus hub.
    let tip = CGPoint(x: center.x + cos(end) * (r - 95), y: center.y + sin(end) * (r - 95))
    c.setLineWidth(30)
    c.move(to: center); c.addLine(to: tip)
    c.setStrokeColor(rgb(0xF5EFE6)); c.strokePath()
    c.setFillColor(rgb(0xF5EFE6))
    c.fillEllipse(in: CGRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
}

for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1)] {
    let px = pt * scale
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    draw(ctx)
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
    try! png.write(to: out.appendingPathComponent(name))
}
