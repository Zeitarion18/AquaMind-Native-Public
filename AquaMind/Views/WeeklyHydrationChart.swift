import SwiftUI

/// 0.4.2: a single native seven-column layout drives the bar positions AND
/// the corresponding day labels. This avoids mismatched Swift Charts insets.
struct WeeklyHydrationChart: View {
    let report: AnalyticsReport

    private let plotHeight: CGFloat = 196
    private let labelHeight: CGFloat = 26
    private let axisWidth: CGFloat = 47

    private var slots: [WeeklyChartSlot] {
        WeeklyChartLayout.slots(report: report)
    }

    private var axisMaximum: Int {
        WeeklyChartLayout.axisMaximum(slots: slots)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            valueAxis
                .frame(width: axisWidth, height: plotHeight)

            GeometryReader { geometry in
                let columnWidth = WeeklyChartLayout.columnWidth(
                    plotWidth: geometry.size.width
                )
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        gridlines
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(slots) { slot in
                                barColumn(slot, width: columnWidth)
                            }
                        }
                    }
                    .frame(height: plotHeight)

                    // Identical column widths to the bars directly above.
                    HStack(spacing: 0) {
                        ForEach(slots) { slot in
                            Text(slot.label)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AquaTheme.muted)
                                .frame(width: columnWidth, height: labelHeight)
                                .accessibilityLabel(slot.label)
                        }
                    }
                }
            }
            .frame(height: plotHeight + labelHeight)
        }
        .frame(height: plotHeight + labelHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Количество жидкости за неделю")
    }

    private var valueAxis: some View {
        GeometryReader { geometry in
            ForEach(0..<5, id: \.self) { tick in
                let value = axisMaximum - tick * (axisMaximum / 4)
                Text(value.formatted(.number))
                    .font(.system(size: 10))
                    .foregroundStyle(AquaTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .position(
                        x: geometry.size.width / 2,
                        y: min(geometry.size.height - 7,
                               max(7, CGFloat(tick) * geometry.size.height / 4))
                    )
            }
        }
    }

    private var gridlines: some View {
        GeometryReader { geometry in
            Path { path in
                for step in 0...4 {
                    let y = CGFloat(step) * geometry.size.height / 4
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                }
            }
            .stroke(Color.white.opacity(0.09), lineWidth: 0.7)
        }
    }

    private func barColumn(_ slot: WeeklyChartSlot, width: CGFloat) -> some View {
        let maxVolume = max(1, axisMaximum)
        let barWidth = min(20, width * 0.48)

        return VStack(spacing: 0) {
            // Reverse draw order so water stays at the bottom of a stack.
            ForEach(Array(slot.segments.reversed())) { segment in
                Rectangle()
                    .fill(segment.tint)
                    .frame(height: plotHeight * CGFloat(segment.milliliters)
                           / CGFloat(maxVolume))
            }
        }
        .frame(width: barWidth)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .frame(width: width, height: plotHeight, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(slot.label): \(slot.total) мл")
    }
}
