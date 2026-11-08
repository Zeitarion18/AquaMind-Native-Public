import Foundation

/// Geometry shared by the SwiftUI renderer and pure Swift regression tests.
/// Segment start/end values remain unchanged for volume accounting.
enum AuroraRingGeometry {
    static let strokeWidth = 17.0
    /// Keep the bubble-only mask just inside the painted stroke. On an iPhone
    /// Retina display the 0.55pt inset is larger than one antialias fringe.
    static let bubbleMaskInset = 0.55
    static let bubbleMaskStrokeWidth = strokeWidth - 2 * bubbleMaskInset
    static let bubbleCanvasPadding = 30.0

    struct RoundedArc: Equatable {
        let start: Double
        let end: Double
    }

    struct Bubble: Equatable {
        /// Offsets from the center of the ring, in SwiftUI's down-positive y.
        let x: Double
        let y: Double
        let diameter: Double
        let opacity: Double
        let radius: Double
    }

    /// Round stroke caps extend half the line width past their path endpoint.
    /// Move the path endpoints inward by the matching arc length so colors
    /// meet softly instead of stacking their round caps on top of one another.
    /// Tiny segments stay visible as rounded dots.
    static func roundedArc(start: Double, end: Double,
                           diameter: Double, lineWidth: Double = strokeWidth) -> RoundedArc {
        let low = min(1, max(0, start))
        let high = min(1, max(low, end))
        let span = high - low
        guard span > 0 else { return RoundedArc(start: low, end: low) }
        let radius = max(1, diameter * 0.5)
        let halfCapFraction = (lineWidth * 0.5) / (2 * .pi * radius)
        // Leave ~0.5px at the interface, preventing visible color overlap.
        let trim = min(span * 0.49, halfCapFraction + 0.00035)
        return RoundedArc(start: low + trim, end: high - trim)
    }

    /// All effects are deterministic: reopening the screen does not move any
    /// endpoint or alter the stored percentage. Each bubble loops independently.
    static func bubble(start: Double, end: Double, time: TimeInterval,
                       index: Int, totalCount: Int, ringRadius: Double,
                       strokeWidth: Double = strokeWidth) -> Bubble {
        let count = max(1, totalCount)
        let phaseOffset = Double(index) / Double(count)
        let duration = 6.2 + Double(index % 4) * 0.9
        let timeUnits = max(0, time) / duration + phaseOffset
        let fraction = timeUnits - floor(timeUnits)
        let span = max(0, end - start)
        let position = start + span * fraction

        // A bubble enters from beyond either side of the annular band,
        // follows its centerline, then leaves past the same band edge.
        // Alternate inner/outer edges for a more natural water flow.
        let side = index.isMultiple(of: 2) ? 1.0 : -1.0
        let entrance = max(0, (0.23 - fraction) / 0.23)
        let exit = max(0, (fraction - 0.77) / 0.23)
        let edgeTravel = min(1, max(entrance, exit))
        let outsideDistance = strokeWidth * 0.5 + 10.5
        let wobble = 0.8 * sin(time * 0.68 + Double(index) * 2.3)
        let radius = max(1, ringRadius + side * edgeTravel * outsideDistance + wobble)

        let radians = 2 * Double.pi * position - Double.pi * 0.5
        // Fade in and out: the phase wrap from 1 to 0 is invisible.
        let fadeIn = min(1, fraction / 0.22)
        let fadeOut = min(1, (1 - fraction) / 0.22)
        let visibility = max(0, min(fadeIn, fadeOut))
        let diameter = 3.3 + Double(index % 4) * 0.9
        return Bubble(
            x: radius * cos(radians),
            y: radius * sin(radians),
            diameter: diameter,
            opacity: visibility * (0.58 + Double(index % 3) * 0.10),
            radius: radius
        )
    }

    static func bubbleCount(forSpan span: Double) -> Int {
        guard span > 0.011 else { return 0 }
        return min(5, max(2, Int(ceil(span * 14))))
    }
}
