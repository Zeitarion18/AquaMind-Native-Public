import SwiftUI

/// Aurora Ring Liquid Polish:
/// precise circular arcs, softly rounded joints and independent bubble streams.
/// Everything is visual; stored percentages and drink identities are unchanged.
struct LiquidProgressRing: View {
    let slices: [HydrationRingSlice]

    @AppStorage("AquaMind.auroraShimmer") private var shimmerEnabled = true
    @AppStorage("AquaMind.auroraGlow") private var glowEnabled = true
    @AppStorage("AquaMind.auroraFill") private var fillEnabled = true
    @AppStorage("AquaMind.auroraBubbles") private var bubblesEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var liveEffects: Bool {
        scenePhase == .active && !reduceMotion &&
            (bubblesEnabled || shimmerEnabled || glowEnabled)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !liveEffects)) { timeline in
            GeometryReader { geometry in
                let diameter = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.08),
                                lineWidth: CGFloat(AuroraRingGeometry.strokeWidth))

                    ForEach(slices) { slice in
                        AuroraDrinkArc(
                            slice: slice,
                            diameter: diameter,
                            time: liveEffects
                                ? timeline.date.timeIntervalSinceReferenceDate : 0,
                            shimmer: shimmerEnabled && liveEffects,
                            glow: glowEnabled,
                            pulsing: glowEnabled && liveEffects,
                            bubbles: bubblesEnabled && liveEffects,
                            fillAnimation: fillEnabled && !reduceMotion
                        )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .accessibilityLabel("Круг дневного прогресса с закруглёнными цветными сегментами напитков")
    }
}

private struct AuroraDrinkArc: View {
    let slice: HydrationRingSlice
    let diameter: CGFloat
    let time: TimeInterval
    let shimmer: Bool
    let glow: Bool
    let pulsing: Bool
    let bubbles: Bool
    let fillAnimation: Bool

    @State private var arcStart: Double
    @State private var arcEnd: Double

    init(slice: HydrationRingSlice, diameter: CGFloat, time: TimeInterval,
         shimmer: Bool, glow: Bool, pulsing: Bool,
         bubbles: Bool, fillAnimation: Bool) {
        self.slice = slice
        self.diameter = diameter
        self.time = time
        self.shimmer = shimmer
        self.glow = glow
        self.pulsing = pulsing
        self.bubbles = bubbles
        self.fillAnimation = fillAnimation
        _arcStart = State(initialValue: slice.start)
        _arcEnd = State(initialValue: fillAnimation ? slice.start : slice.end)
    }

    private var activeSpan: Double { max(0, arcEnd - arcStart) }

    private var range: AuroraRingGeometry.RoundedArc {
        AuroraRingGeometry.roundedArc(
            start: arcStart,
            end: arcEnd,
            diameter: Double(diameter))
    }

    private var pulse: Double {
        pulsing ? 0.24 + 0.08 * sin(time * 1.05 + slice.start * 10) : 0.25
    }

    var body: some View {
        ZStack {
            if glow && activeSpan > 0 {
                Circle()
                    .trim(from: range.start, to: range.end)
                    .stroke(
                        slice.identity.tint.opacity(pulse),
                        style: StrokeStyle(lineWidth: 21, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 6.5)
            }

            Circle()
                .trim(from: range.start, to: range.end)
                .stroke(
                    LinearGradient(
                        colors: [
                            slice.identity.isCustom
                                ? slice.identity.tint.opacity(0.64)
                                : slice.kind.shadowTint.opacity(0.97),
                            slice.identity.tint,
                            slice.identity.tint.opacity(0.96)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(
                        lineWidth: CGFloat(AuroraRingGeometry.strokeWidth),
                        lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Diffuse moving sheen across the whole liquid surface. It
            // intentionally has no thin white dashes (0.7.3 behavior).
            if shimmer && activeSpan > 0.02 {
                Circle()
                    .trim(from: range.start, to: range.end)
                    .stroke(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.02),
                                .white.opacity(0.17),
                                .white.opacity(0.025)
                            ],
                            startPoint: UnitPoint(
                                x: 0.5 + 0.45 * cos(time * 0.27), y: 0),
                            endPoint: UnitPoint(
                                x: 0.5 - 0.45 * cos(time * 0.27), y: 1)
                        ),
                        style: StrokeStyle(lineWidth: 7.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .blur(radius: 2.5)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            if bubbles && activeSpan > 0.011 {
                bubbleCanvas
            }
        }
        .onAppear {
            if fillAnimation {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.89)) {
                    arcEnd = slice.end
                }
            } else {
                arcEnd = slice.end
            }
        }
        .onChange(of: slice) { _, updated in
            if fillAnimation {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.89)) {
                    arcStart = updated.start
                    arcEnd = updated.end
                }
            } else {
                arcStart = updated.start
                arcEnd = updated.end
            }
        }
        .onChange(of: fillAnimation) { _, enabled in
            if !enabled {
                arcStart = slice.start
                arcEnd = slice.end
            }
        }
    }

    private var bubbleCanvas: some View {
        // Keep the canvas larger so the animated centers can travel outside,
        // BUT render the bubbles through a hard liquid-only mask below.
        // Only the portion physically inside the colored rounded arc appears.
        let extra = CGFloat(AuroraRingGeometry.bubbleCanvasPadding)
        return Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let count = AuroraRingGeometry.bubbleCount(forSpan: activeSpan)
            guard count > 0 else { return }

            for index in 0..<count {
                let b = AuroraRingGeometry.bubble(
                    start: arcStart, end: arcEnd, time: time,
                    index: index, totalCount: count,
                    ringRadius: Double(diameter) / 2)
                guard b.opacity > 0.025 else { continue }

                let d = CGFloat(b.diameter)
                let x = center.x + CGFloat(b.x)
                let y = center.y + CGFloat(b.y)
                let rect = CGRect(
                    x: x - d / 2,
                    y: y - d / 2,
                    width: d,
                    height: d)
                let outline = Path(ellipseIn: rect)
                // An outlined orb, not a moving white line.
                context.fill(outline,
                             with: .color(slice.identity.tint.opacity(b.opacity * 0.25)))
                context.stroke(outline,
                               with: .color(.white.opacity(b.opacity * 0.82)),
                               lineWidth: 0.88)
                let shine = CGRect(
                    x: rect.minX + d * 0.22,
                    y: rect.minY + d * 0.17,
                    width: max(CGFloat(0.65), d * 0.24),
                    height: max(CGFloat(0.65), d * 0.24))
                context.fill(Path(ellipseIn: shine),
                             with: .color(.white.opacity(b.opacity * 0.78)))
            }
        }
        .frame(width: diameter + extra * 2, height: diameter + extra * 2)
        .mask {
            // Use the SAME trimmed Circle and rounded cap geometry as the
            // actual painted liquid segment. A tiny inset prevents antialias
            // fringes from leaking even a pixel beyond the colored boundary.
            // Unlike opacity fades, this clips each partially-entering orb
            // at the precise inner/outer edge AND both round end-caps.
            Circle()
                .trim(from: range.start, to: range.end)
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: CGFloat(AuroraRingGeometry.bubbleMaskStrokeWidth),
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .frame(width: diameter, height: diameter)
                .frame(width: diameter + extra * 2, height: diameter + extra * 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
