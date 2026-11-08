import Foundation

@main
struct AuroraRingGeometryTests {
    static func main() {
        let width = AuroraRingGeometry.strokeWidth
        let diameter = 218.0
        let radius = diameter / 2

        // Stroke caps extend in both directions. Insets keep the rounded
        // ends of adjacent colors just apart without overlapping each other.
        let first = AuroraRingGeometry.roundedArc(
            start: 0, end: 0.25, diameter: diameter)
        let second = AuroraRingGeometry.roundedArc(
            start: 0.25, end: 0.5, diameter: diameter)
        let capFraction = width / 2 / (2 * Double.pi * radius)
        assert(first.start > 0)
        assert(first.end < 0.25)
        assert(second.start > 0.25)
        assert(second.end < 0.5)
        assert(first.end + capFraction < second.start - capFraction,
               "Round color caps should not overlap at a shared boundary")
        let visibleGap = (second.start - capFraction) -
                         (first.end + capFraction)
        assert(visibleGap > 0 && visibleGap < 0.003,
               "Rounded caps must remain almost touching, not form large gaps")

        // Tiny amounts are still visible as little colored pearls, never
        // with an invalid negative trim range.
        for span in [0.0001, 0.003, 0.012, 0.02, 0.045, 0.50, 1.0] {
            let trim = AuroraRingGeometry.roundedArc(
                start: 0, end: span, diameter: diameter)
            assert(trim.start >= 0 && trim.start < trim.end && trim.end <= span)
            assert(trim.end.isFinite && trim.start.isFinite)
        }
        let empty = AuroraRingGeometry.roundedArc(
            start: 0.7, end: 0.7, diameter: diameter)
        assert(empty.start == empty.end)

        // Bubbles are round and move across BOTH sides of the annular band.
        let outerStart = AuroraRingGeometry.bubble(
            start: 0.10, end: 0.30, time: 6.2 * 0.10,
            index: 0, totalCount: 2, ringRadius: radius)
        let innerStart = AuroraRingGeometry.bubble(
            start: 0.10, end: 0.30, time: 7.1 * 0.60,
            index: 1, totalCount: 2, ringRadius: radius)
        assert(outerStart.radius > radius + width / 2,
               "Some bubbles must enter beyond the outer edge")
        assert(innerStart.radius < radius - width / 2,
               "Other bubbles must enter beyond the inner edge")
        assert(outerStart.opacity > 0 && innerStart.opacity > 0)

        let outerExit = AuroraRingGeometry.bubble(
            start: 0.10, end: 0.30, time: 6.2 * 0.90,
            index: 0, totalCount: 2, ringRadius: radius)
        let innerExit = AuroraRingGeometry.bubble(
            start: 0.10, end: 0.30, time: 7.1 * 1.40,
            index: 1, totalCount: 2, ringRadius: radius)
        assert(outerExit.radius > radius + width / 2)
        assert(innerExit.radius < radius - width / 2)
        let settled = AuroraRingGeometry.bubble(
            start: 0.10, end: 0.30, time: 6.2 * 0.50,
            index: 0, totalCount: 2, ringRadius: radius)
        assert(abs(settled.radius - radius) <= 1,
               "Bubbles should move inside the colored band")
        assert(settled.opacity > 0.50)
        assert(settled.diameter > 0 && settled.diameter < width)

        // Timing wraps invisibly, so no hard white flash when a new orb starts.
        let atBirth = AuroraRingGeometry.bubble(
            start: 0, end: 0.20, time: 0,
            index: 0, totalCount: 3, ringRadius: radius)
        let nearEnd = AuroraRingGeometry.bubble(
            start: 0, end: 0.20, time: 6.2 * 0.995,
            index: 0, totalCount: 3, ringRadius: radius)
        assert(atBirth.opacity == 0)
        assert(nearEnd.opacity < 0.03)

        // Determinism: redraws with the same clock produce the same bubble.
        let again = AuroraRingGeometry.bubble(
            start: 0.10, end: 0.30, time: 6.2 * 0.50,
            index: 0, totalCount: 2, ringRadius: radius)
        assert(again == settled)
        assert(AuroraRingGeometry.bubbleCount(forSpan: 0) == 0)
        assert(AuroraRingGeometry.bubbleCount(forSpan: 0.20) >= 2)
        assert(AuroraRingGeometry.bubbleCount(forSpan: 1) <= 5)

        // Visual effects do not change the data model: the 950ml ring retains
        // precisely the same share of a 2000ml goal.
        let now = Date(timeIntervalSince1970: 1_783_260_000)
        let entries = [
            WaterEntry(date: now, milliliters: 500, kind: .water),
            WaterEntry(date: now, milliliters: 100, kind: .milk),
            WaterEntry(date: now, milliliters: 350, kind: .other,
                       customDrinkName: "Бабл-ти", customDrinkPalette: 8)
        ]
        let segments = HydrationRing.segments(entries: entries, goal: 2000)
        assert(segments.count == 3)
        assert(abs(segments.last!.end - 0.475) < 0.0000001)
        assert(segments.contains { $0.identity.title == "Бабл-ти" })
        assert(segments.contains { $0.identity.customPalette == 8 })
        assert(segments.allSatisfy { segment in
            let arc = AuroraRingGeometry.roundedArc(
                start: segment.start, end: segment.end, diameter: diameter)
            return arc.start >= segment.start && arc.end <= segment.end
        })

        print("AquaMind 0.7.4 tests passed: rounded joints, two-sided bubbles, fade, zero motion data changes, personal colors")
    }
}
