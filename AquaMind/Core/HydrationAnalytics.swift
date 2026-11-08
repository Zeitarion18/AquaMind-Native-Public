import Foundation

enum AnalyticsSpan: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return "День"
        case .week: return "Неделя"
        case .month: return "Месяц"
        }
    }
    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
    var previousTitle: String {
        switch self {
        case .day: return "Предыдущий день"
        case .week: return "Предыдущая неделя"
        case .month: return "Предыдущий месяц"
        }
    }
}

/// Separates user-defined beverages from the built-in "Другое" category.
/// Historical snapshots are the source of truth, even if a custom drink was
/// subsequently renamed or deleted in settings.
struct AnalyticsDrinkIdentity: Hashable, Identifiable {
    let kind: DrinkKind
    let customName: String?
    let customID: UUID?
    let customSymbol: String?
    let customPalette: Int?

    init(entry: WaterEntry, profiles: [CustomDrink] = []) {
        kind = entry.kind
        let namedProfile: CustomDrink? = {
            guard let name = entry.customDrinkName else { return nil }
            return profiles.first {
                $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
        }()
        let profile = entry.customDrinkID.flatMap { id in
            profiles.first(where: { $0.id == id })
        } ?? namedProfile
        customID = profile?.id ?? entry.customDrinkID
        customName = profile?.name ?? entry.customDrinkName
        customSymbol = profile?.symbol ?? entry.customDrinkSymbol
        customPalette = profile?.palette ?? entry.customDrinkPalette
    }

    var id: String {
        if let id = customID { return "custom-id|\(id.uuidString)" }
        if let name = customName {
            // Legacy records without profile IDs remain distinct from "Other".
            return "custom-legacy|\(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))|\(customPalette ?? 0)|\(customSymbol ?? "drop.fill")"
        }
        return kind.rawValue
    }
    var title: String { customName ?? kind.title }
    var isCustom: Bool { customName != nil }
}

struct AnalyticsBucket: Identifiable {
    let index: Int
    let identity: AnalyticsDrinkIdentity
    let milliliters: Int
    var id: String { "\(index)-\(identity.id)" }
    var kind: DrinkKind { identity.kind }
    var title: String { identity.title }
}

struct AnalyticsDrink: Identifiable {
    let identity: AnalyticsDrinkIdentity
    let milliliters: Int
    let records: Int
    var id: String { identity.id }
    var kind: DrinkKind { identity.kind }
    var title: String { identity.title }
}

struct AnalyticsReport {
    let span: AnalyticsSpan
    let range: DateInterval
    let title: String
    let total: Int
    let previousTotal: Int
    let averagePerDay: Int
    let activeDays: Int
    let recordCount: Int
    let numberOfDays: Int
    let isCurrentPeriod: Bool
    let buckets: [AnalyticsBucket]
    let bucketLabels: [String]
    let axisMarks: [Int]
    let drinks: [AnalyticsDrink]

    var percentageChange: Double? {
        guard previousTotal > 0 else { return nil }
        return 100 * Double(total - previousTotal) / Double(previousTotal)
    }
    var topDrink: AnalyticsDrink? { drinks.first }
}

/// Deterministic, local-only calculations. Never modifies hydration.json or its records.
/// All date grouping respects the user's chosen AquaMind time zone.
enum HydrationAnalytics {
    static func mondayCalendar(_ source: Calendar) -> Calendar {
        var calendar = source
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    static func periodRange(span: AnalyticsSpan, anchor: Date, calendar: Calendar) -> DateInterval {
        let cal = mondayCalendar(calendar)
        return cal.dateInterval(of: span.component, for: anchor)
            ?? cal.dateInterval(of: .day, for: anchor)
            ?? DateInterval(start: cal.startOfDay(for: anchor), duration: 86_400)
    }

    static func report(entries: [WaterEntry], span: AnalyticsSpan,
                       anchor: Date, now: Date = Date(),
                       calendar: Calendar,
                       profiles: [CustomDrink] = []) -> AnalyticsReport {
        let cal = mondayCalendar(calendar)
        let range = periodRange(span: span, anchor: anchor, calendar: cal)
        let currentPeriod = range.start <= now && now < range.end
        let end = currentPeriod ? now : min(now, range.end)
        let actualEnd = max(range.start, end)

        let previousStart = cal.date(byAdding: span.component, value: -1, to: range.start)
            ?? range.start.addingTimeInterval(-range.duration)
        // Fair comparison: an incomplete current period is compared with the
        // same elapsed duration of the previous period, not its entire length.
        let previousEnd = currentPeriod
            ? min(range.start, previousStart.addingTimeInterval(actualEnd.timeIntervalSince(range.start)))
            : range.start

        let matching = entries.filter {
            $0.milliliters > 0 && $0.date >= range.start && $0.date <= now && $0.date < range.end
        }
        let earlier = entries.filter {
            $0.milliliters > 0 && $0.date >= previousStart && $0.date < previousEnd
        }

        let total = matching.reduce(0) { $0 + $1.milliliters }
        let previousTotal = earlier.reduce(0) { $0 + $1.milliliters }
        let totalDays: Int
        switch span {
        case .day: totalDays = 1
        case .week: totalDays = 7
        case .month: totalDays = cal.range(of: .day, in: .month, for: range.start)?.count ?? 30
        }

        // A day has one day for averaging, but 24 hourly chart buckets.
        let bucketCount = span == .day ? 24 : totalDays

        let elapsedDays: Int
        if currentPeriod {
            let elapsed = cal.dateComponents([.day], from: range.start,
                                             to: cal.startOfDay(for: now)).day ?? 0
            elapsedDays = min(totalDays, max(1, elapsed + 1))
        } else {
            elapsedDays = totalDays
        }
        let activeDays = Set(matching.map { cal.startOfDay(for: $0.date) }).count

        var counts: [AnalyticsDrinkIdentity: (milliliters: Int, records: Int)] = [:]
        var byBucket: [Int: [AnalyticsDrinkIdentity: Int]] = [:]
        for entry in matching {
            let key = AnalyticsDrinkIdentity(entry: entry, profiles: profiles)
            var value = counts[key] ?? (0, 0)
            value.milliliters += entry.milliliters
            value.records += 1
            counts[key] = value

            let index: Int
            switch span {
            case .day:
                index = cal.component(.hour, from: entry.date)
            case .week:
                index = cal.dateComponents([.day], from: range.start,
                                           to: cal.startOfDay(for: entry.date)).day ?? -1
            case .month:
                index = cal.component(.day, from: entry.date) - 1
            }
            guard index >= 0 && index < bucketCount else { continue }
            byBucket[index, default: [:]][key, default: 0] += entry.milliliters
        }

        let identities = counts.keys.sorted { lhs, rhs in
            // Built-in categories keep their old order; custom names follow.
            let lrank = DrinkKind.allCases.firstIndex(of: lhs.kind) ?? 100
            let rrank = DrinkKind.allCases.firstIndex(of: rhs.kind) ?? 100
            if lrank != rrank { return lrank < rrank }
            return lhs.id < rhs.id
        }
        let drinks: [AnalyticsDrink] = identities.compactMap { key in
            guard let c = counts[key], c.milliliters > 0 else { return nil }
            return AnalyticsDrink(identity: key, milliliters: c.milliliters,
                                  records: c.records)
        }.sorted { lhs, rhs in
            if lhs.milliliters != rhs.milliliters {
                return lhs.milliliters > rhs.milliliters
            }
            return lhs.id < rhs.id
        }

        let buckets: [AnalyticsBucket] = (0..<bucketCount).flatMap { index in
            identities.compactMap { key -> AnalyticsBucket? in
                guard let amount = byBucket[index]?[key], amount > 0 else { return nil }
                return AnalyticsBucket(index: index, identity: key,
                                       milliliters: amount)
            }
        }
        let labels: [String]
        switch span {
        case .day:
            labels = (0..<24).map { String(format: "%02d", $0) }
        case .week:
            labels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
        case .month:
            labels = (1...totalDays).map(String.init)
        }
        let marks: [Int]
        switch span {
        case .day:
            marks = [0, 4, 8, 12, 16, 20, 23]
        case .week:
            marks = Array(0..<7)
        case .month:
            marks = Array(Set([0, 4, 9, 14, 19, 24, 29, totalDays - 1]
                .filter { $0 < totalDays })).sorted()
        }

        return AnalyticsReport(
            span: span, range: range,
            title: title(for: range, span: span, timeZone: cal.timeZone),
            total: total, previousTotal: previousTotal,
            averagePerDay: total / elapsedDays, activeDays: activeDays,
            recordCount: matching.count, numberOfDays: elapsedDays,
            isCurrentPeriod: currentPeriod, buckets: buckets,
            bucketLabels: labels, axisMarks: marks, drinks: drinks)
    }

    static func calendarDays(month: Date, calendar: Calendar) -> [Date?] {
        let cal = mondayCalendar(calendar)
        guard let range = cal.dateInterval(of: .month, for: month),
              let days = cal.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = cal.component(.weekday, from: range.start)
        let padding = (weekday + 5) % 7 // Monday is the first column
        var result: [Date?] = Array(repeating: nil, count: padding)
        for number in days {
            result.append(cal.date(byAdding: .day, value: number - 1, to: range.start))
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    static func calendarTotals(entries: [WaterEntry], month: Date,
                               calendar: Calendar) -> [Date: Int] {
        let cal = mondayCalendar(calendar)
        guard let range = cal.dateInterval(of: .month, for: month) else { return [:] }
        var totals: [Date: Int] = [:]
        for entry in entries where entry.milliliters > 0 &&
                entry.date >= range.start && entry.date < range.end {
            totals[cal.startOfDay(for: entry.date), default: 0] += entry.milliliters
        }
        return totals
    }

    static func title(for range: DateInterval, span: AnalyticsSpan,
                      timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = timeZone
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        formatter.calendar = cal
        switch span {
        case .day:
            formatter.dateFormat = "d MMMM yyyy"
            return formatter.string(from: range.start)
        case .month:
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: range.start)
        case .week:
            formatter.dateFormat = "d MMM"
            let start = formatter.string(from: range.start)
            let last = cal.date(byAdding: .day, value: -1, to: range.end) ?? range.end
            return "\(start) — \(formatter.string(from: last))"
        }
    }
}


/// A shared seven-column geometry model for AquaMind's weekly chart.
/// Each slot owns both the stacked bar and its weekday label.
struct WeeklyChartSlot: Identifiable {
    let index: Int
    let label: String
    let segments: [AnalyticsBucket]
    var id: Int { index }
    var total: Int { segments.reduce(0) { $0 + $1.milliliters } }
}

enum WeeklyChartLayout {
    static func slots(report: AnalyticsReport) -> [WeeklyChartSlot] {
        precondition(report.span == .week, "Week slots require a week report")
        return (0..<7).map { index in
            let parts = report.buckets.filter { $0.index == index && $0.milliliters > 0 }
            return WeeklyChartSlot(index: index, label: report.bucketLabels[index],
                                   segments: parts)
        }
    }

    static func axisMaximum(slots: [WeeklyChartSlot]) -> Int {
        let highest = slots.map(\.total).max() ?? 0
        let step: Int
        if highest <= 400 { step = 100 }
        else if highest <= 1000 { step = 250 }
        else if highest <= 2000 { step = 500 }
        else { step = 1000 }
        let whole = step * 4
        return max(whole, ((highest + whole - 1) / whole) * whole)
    }

    /// The same width is applied to the column containing the bar AND
    /// the label, so alignment cannot drift when the available width changes.
    static func columnWidth(plotWidth: CGFloat) -> CGFloat { plotWidth / 7 }

    static func centerX(index: Int, plotWidth: CGFloat) -> CGFloat {
        (CGFloat(index) + 0.5) * columnWidth(plotWidth: plotWidth)
    }
}
