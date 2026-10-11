import SwiftUI
import AppKit

/// The app icon's snowflake as a template image, so macOS tints it for light, dark,
/// Increase Contrast and Liquid Glass menu bars.
enum MenuBarIcon {
    static let image = snowflake(size: 18, lineWidth: 1.25, label: "TCLimate")

    /// Draws the snowflake at its target point size so it stays crisp when used larger in the panel.
    /// Six rays, each with one small branch near its tip (matches the app icon).
    static func snowflake(size: CGFloat, lineWidth: CGFloat, label: String? = nil) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY), length = rect.width * 0.46 - lineWidth / 2
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            for arm in 0..<6 {
                let angle = CGFloat.pi / 2 + CGFloat(arm) * .pi / 3
                path.move(to: center)
                path.line(to: CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length))
                let branch = CGPoint(x: center.x + cos(angle) * length * 0.685, y: center.y + sin(angle) * length * 0.685)
                for side in [-1.0, 1.0] {
                    let branchAngle = angle + CGFloat(side) * .pi / 4
                    path.move(to: branch)
                    path.line(to: CGPoint(x: branch.x + cos(branchAngle) * length * 0.26, y: branch.y + sin(branchAngle) * length * 0.26))
                }
            }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = label
        return image
    }
}
