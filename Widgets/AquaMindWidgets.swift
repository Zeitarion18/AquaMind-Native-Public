import WidgetKit
import SwiftUI

struct AquaMindEntry: TimelineEntry {
    let date: Date
    let snapshot: AquaMindWidgetSnapshot?
}

struct AquaMindTimeline: TimelineProvider {
    func placeholder(in context: Context) -> AquaMindEntry {
        AquaMindEntry(date: Date(), snapshot: AquaMindWidgetSnapshot(
            dayKey: AquaMindWidgetSnapshot.dayKey(Date(), timeZone: .current),
            zoneID: TimeZone.current.identifier,
            milliliters: 1250, dailyGoal: 2000,
            portions: [.init(kind: "water", milliliters: 1000),
                       .init(kind: "tea", milliliters: 250)],
            updatedAt: Date()
        ))
    }
    func getSnapshot(in context: Context,
                     completion: @escaping (AquaMindEntry) -> Void) {
        completion(AquaMindEntry(
            date: Date(),
            snapshot: AquaMindWidgetStore.load()))
    }
    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<AquaMindEntry>) -> Void) {
        let now = Date()
        let item = AquaMindEntry(date: now, snapshot: AquaMindWidgetStore.load(now: now))
        // The host app calls WidgetCenter.reloadTimelines after every entry.
        // This fallback refresh also clears stale totals near the day boundary.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now)!
        completion(Timeline(entries: [item], policy: .after(next)))
    }
}

private enum WidgetPalette {
    static let cyan = Color(red: 0.28, green: 0.87, blue: 0.96)
    static let bg = Color(red: 0.045, green: 0.09, blue: 0.16)
    static func kindColor(_ key: String) -> Color {
        switch key {
        case "water": return cyan
        case "tea": return Color(red: 0.79, green: 0.58, blue: 0.32)
        case "coffee": return Color(red: 0.55, green: 0.31, blue: 0.19)
        case "juice": return Color(red: 1, green: 0.68, blue: 0.22)
        case "soda": return Color(red: 0.65, green: 0.45, blue: 1)
        case "milk": return Color(red: 0.83, green: 0.92, blue: 1)
        case "compote": return Color(red: 1, green: 0.38, blue: 0.62)
        case "broth": return Color(red: 0.94, green: 0.74, blue: 0.25)
        default: return .gray
        }
    }
}

private struct AquaMindWidgetView: View {
    let entry: AquaMindEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: AquaMindWidgetSnapshot? {
        entry.snapshot?.current(on: entry.date)
    }
    private var total: Int { snapshot?.milliliters ?? 0 }
    private var goal: Int { snapshot?.dailyGoal ?? 2000 }
    private var progress: Double { snapshot?.progress ?? 0 }
    private let sizes: [Int] = [150, 250, 350]

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                medium
            case .accessoryCircular:
                accessory
            default:
                small
            }
        }
        .containerBackground(WidgetPalette.bg, for: .widget)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("AQUAMIND", systemImage: "drop.fill")
                .font(.caption.bold()).foregroundStyle(WidgetPalette.cyan)
            Spacer(minLength: 2)
            HStack {
                ring.frame(width: 58, height: 58)
                Spacer(minLength: 0)
            }
            Text("\(total) / \(goal) мл")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75).lineLimit(1)
            Text(snapshot == nil ? "Открой AquaMind для обновления" : "Баланс за сегодня")
                .font(.caption2).foregroundStyle(.white.opacity(0.68))
                .lineLimit(2)
        }
        .padding(8)
        .widgetURL(URL(string: "aquamind://home"))
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                Text("AQUAMIND")
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(WidgetPalette.cyan)
                ring.frame(width: 84, height: 84)
                Text("\(total) / \(goal) мл")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 2)
            VStack(alignment: .leading, spacing: 10) {
                Text("Добавить воду")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                ForEach(sizes, id: \.self) { amount in
                    Link(destination: URL(string: "aquamind://add?amount=\(amount)")!) {
                        HStack(spacing: 7) {
                            Image(systemName: "plus.circle.fill")
                            Text("+\(amount) мл")
                            Spacer(minLength: 0)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetPalette.cyan)
                        .padding(.horizontal, 11)
                        .frame(height: 29)
                        .background(WidgetPalette.cyan.opacity(0.13),
                                    in: RoundedRectangle(cornerRadius: 9))
                    }
                }
                Text("Нажатие откроет приложение")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(8)
    }

    private var accessory: some View {
        ring.frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetURL(URL(string: "aquamind://home"))
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(WidgetPalette.cyan.opacity(0.16), lineWidth: 6)
            if let snapshot = snapshot, !snapshot.portions.isEmpty {
                let denom = Double(max(goal, total, 1))
                ForEach(Array(snapshot.portions.enumerated()), id: \.offset) { index, portion in
                    let start = Double(snapshot.portions.prefix(index).reduce(0) {
                        $0 + $1.milliliters
                    }) / denom
                    let end = start + Double(portion.milliliters) / denom
                    Circle()
                        .trim(from: start, to: min(1, end))
                        .stroke(WidgetPalette.kindColor(portion.kind),
                                style: StrokeStyle(lineWidth: 6, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(WidgetPalette.cyan, lineWidth: 6)
                    .rotationEffect(.degrees(-90))
            }
            Text("\(Int(progress * 100))%")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.65)
        }
    }
}

struct AquaMindHydrationWidget: Widget {
    let kind = "AquaMindHydration"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AquaMindTimeline()) { entry in
            AquaMindWidgetView(entry: entry)
        }
        .configurationDisplayName("AquaMind · Баланс жидкости")
        .description("Дневной прогресс и быстрый учёт воды.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

@main
struct AquaMindWidgets: WidgetBundle {
    var body: some Widget {
        AquaMindHydrationWidget()
    }
}
