import Foundation
import SwiftUI
import CoreGraphics

/// Pixel regression for the exact rounded Circle stroke used by the view's
/// .mask modifier. Test bubbles crossing both radial edges and both arc caps.
@main
struct AuroraBubbleMaskTests {
    private static let diameter: CGFloat = 218
    private static let padding: CGFloat = 30
    private static let total: CGFloat = diameter + 2 * padding
    private static let center = CGPoint(x: total / 2, y: total / 2)

    private static func trackPath(from: Double, to: Double,
                                  strokeWidth: CGFloat) -> Path {
        let arc = AuroraRingGeometry.roundedArc(
            start: from, end: to, diameter: Double(diameter))
        let base = Path(ellipseIn: CGRect(x: padding, y: padding,
                                         width: diameter, height: diameter))
        let stroke = base
            .trimmedPath(from: arc.start, to: arc.end)
            .strokedPath(StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
        // Identical to Circle.trim.stroke.rotationEffect(-90) about center.
        let x = center.x, y = center.y
        let rotation = CGAffineTransform(translationX: x, y: y)
            .rotated(by: -.pi / 2)
            .translatedBy(x: -x, y: -y)
        return stroke.applying(rotation)
    }

    private static func polar(_ t: Double, _ radius: CGFloat) -> CGPoint {
        let angle = 2 * Double.pi * t - Double.pi / 2
        return CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                       y: center.y + radius * CGFloat(sin(angle)))
    }

    private static func draw(mask: Path, circles: [CGRect], scale: Int = 3) -> [UInt8] {
        let px = Int(total) * scale
        let bytesPerRow = px * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue |
                   CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = CGContext(data: nil, width: px, height: px,
                            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                            space: colorSpace, bitmapInfo: info)!
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        ctx.addPath(mask.cgPath)
        ctx.clip()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        for circle in circles {
            ctx.fillEllipse(in: circle)
        }
        let bytes = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return stride(from: 3, to: px * px * 4, by: 4).map { bytes[$0] }
    }

    private static func circle(at point: CGPoint, diameter: CGFloat) -> CGRect {
        CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
               width: diameter, height: diameter)
    }

    static func main() {
        let painted = trackPath(from: 0.12, to: 0.33,
                                strokeWidth: CGFloat(AuroraRingGeometry.strokeWidth))
        let masked = trackPath(from: 0.12, to: 0.33,
                               strokeWidth: CGFloat(AuroraRingGeometry.bubbleMaskStrokeWidth))
        let ringRadius = diameter / 2
        let outer = ringRadius + CGFloat(AuroraRingGeometry.strokeWidth / 2)
        let inner = ringRadius - CGFloat(AuroraRingGeometry.strokeWidth / 2)

        assert(masked.contains(polar(0.23, ringRadius)), "Mid-band bubble must be visible")
        assert(!masked.contains(polar(0.23, outer + 1.5)),
               "No bubble pixels beyond outer radius")
        assert(!masked.contains(polar(0.23, inner - 1.5)),
               "No bubble pixels beyond inner radius")
        assert(!masked.contains(polar(0.05, ringRadius)),
               "No particles on empty/neighbor segment")
        assert(!masked.contains(polar(0.41, ringRadius)),
               "No particles past the other rounded cap")

        // Each center is only *partially* inside a boundary: the circles must
        // appear as partial disks on entry, and vanish again on exit.
        let partialOuter = circle(at: polar(0.23, outer + 1.0), diameter: 7)
        let partialInner = circle(at: polar(0.23, inner - 1.0), diameter: 7)
        let inBand = circle(at: polar(0.23, ringRadius), diameter: 5)
        let invisibleOuter = circle(at: polar(0.23, outer + 8), diameter: 5)
        let invisibleInner = circle(at: polar(0.23, inner - 8), diameter: 5)
        let outsideArc = circle(at: polar(0.45, ringRadius), diameter: 5)

        let combined = draw(mask: masked, circles: [
            partialOuter, partialInner, inBand,
            invisibleOuter, invisibleInner, outsideArc
        ])
        let paintPixels = draw(mask: painted,
                               circles: [CGRect(x: 0, y: 0,
                                                width: total, height: total)])
        // The narrower clip creates a one-retina-pixel safety margin:
        // no particle pixel may exist outside the actually colored arc.
        for i in combined.indices where combined[i] > 0 {
            assert(paintPixels[i] > 0, "Bubble pixel outside colored segment: \(i)")
        }
        let partialOutPixels = draw(mask: masked, circles: [partialOuter])
            .filter { $0 > 0 }.count
        let partialInPixels = draw(mask: masked, circles: [partialInner])
            .filter { $0 > 0 }.count
        let fullPixels = draw(mask: masked, circles: [inBand])
            .filter { $0 > 0 }.count
        assert(partialOutPixels > 0 && partialInPixels > 0,
               "A partially entered bubble must show a clipped portion")
        assert(partialOutPixels < fullPixels && partialInPixels < fullPixels,
               "Partial bubbles should be smaller than fully visible orbs")
        assert(draw(mask: masked, circles: [invisibleOuter]).allSatisfy { $0 == 0 })
        assert(draw(mask: masked, circles: [invisibleInner]).allSatisfy { $0 == 0 })
        assert(draw(mask: masked, circles: [outsideArc]).allSatisfy { $0 == 0 })

        // Caps: visible near the round tip and completely hidden beyond it.
        let nearCap = circle(at: polar(0.12, ringRadius), diameter: 5)
        let offCap = circle(at: polar(0.07, ringRadius), diameter: 5)
        assert(draw(mask: masked, circles: [nearCap]).contains { $0 > 0 })
        assert(draw(mask: masked, circles: [offCap]).allSatisfy { $0 == 0 })

        // Keep the underlying stored progress exactly as before.
        let logs = [
            WaterEntry(milliliters: 500, kind: .water),
            WaterEntry(milliliters: 100, kind: .milk),
            WaterEntry(milliliters: 350, kind: .other,
                       customDrinkName: "Бабл-ти", customDrinkPalette: 8)
        ]
        let arcs = HydrationRing.segments(entries: logs, goal: 2000)
        assert(abs(arcs.last!.end - 0.475) < 1e-8)

        print("AquaMind 0.7.5 bubble mask passed: retina pixels fully confined, both radial edges, rounded caps, partial entry and exit")
    }
}
