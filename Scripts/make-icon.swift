import AppKit

// Draws the app icon in a 1024×1024 space (origin bottom-left) on Apple's macOS icon grid:
// a thin white snowflake on a flat soft-graphite tile.
func gray(_ value: CGFloat, _ alpha: CGFloat = 1) -> CGColor { CGColor(gray: value, alpha: alpha) }

func drawIcon(_ ctx: CGContext, scale: CGFloat) {
    // Tile, with the standard icon shadow (shadows ignore the CTM, so they're scaled by hand)
    // and a hairline edge so it holds its shape against dark backgrounds.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale, color: gray(0, 0.3))
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setFillColor(gray(0.15)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(gray(1, 0.14)); ctx.setLineWidth(3); ctx.strokePath()

    // Six rays, each with one small branch near its tip.
    let center = CGPoint(x: 512, y: 512)
    for arm in 0..<6 {
        let angle = CGFloat.pi / 2 + CGFloat(arm) * .pi / 3
        ctx.move(to: center)
        ctx.addLine(to: CGPoint(x: center.x + cos(angle) * 270, y: center.y + sin(angle) * 270))
        let branch = CGPoint(x: center.x + cos(angle) * 185, y: center.y + sin(angle) * 185)
        for side in [-1.0, 1.0] {
            let branchAngle = angle + CGFloat(side) * .pi / 4
            ctx.move(to: branch)
            ctx.addLine(to: CGPoint(x: branch.x + cos(branchAngle) * 70, y: branch.y + sin(branchAngle) * 70))
        }
    }
    ctx.setStrokeColor(gray(1)); ctx.setLineWidth(30); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.strokePath()
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = size * factor
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        let scale = CGFloat(pixels) / 1024
        ctx.scaleBy(x: scale, y: scale)
        drawIcon(ctx, scale: scale)
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)\(factor == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
