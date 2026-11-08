import Foundation

/// A non-sensitive, read-only mirror of today's aggregate hydration values.
/// The canonical archive stays in AquaMind's original Application Support folder.
struct AquaMindWidgetSnapshot: Codable, Equatable {
    struct Portion: Codable, Equatable {
        var kind: String
        var milliliters: Int
    }

    var dayKey: String
    var zoneID: String
    var milliliters: Int
    var dailyGoal: Int
    var portions: [Portion]
    var updatedAt: Date

    static func dayKey(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    static func make(entries: [WaterEntry],
                     settings: HydrationSettings,
                     now: Date) -> AquaMindWidgetSnapshot {
        let calendar = settings.calendar
        let current = entries.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let portions = DrinkKind.allCases.compactMap { kind -> Portion? in
            let amount = current.filter { $0.kind == kind }
                .reduce(0) { $0 + max(0, $1.milliliters) }
            return amount == 0 ? nil : Portion(kind: kind.rawValue, milliliters: amount)
        }
        return AquaMindWidgetSnapshot(
            dayKey: dayKey(now, timeZone: settings.timeZone),
            zoneID: settings.timeZone.identifier,
            milliliters: portions.reduce(0) { $0 + $1.milliliters },
            dailyGoal: max(1, settings.dailyGoal),
            portions: portions,
            updatedAt: now
        )
    }

    /// Avoid showing yesterday's numbers at midnight when iOS delays widget updates.
    func current(on now: Date) -> AquaMindWidgetSnapshot {
        let zone = TimeZone(identifier: zoneID) ?? .current
        guard dayKey == Self.dayKey(now, timeZone: zone) else {
            return AquaMindWidgetSnapshot(
                dayKey: Self.dayKey(now, timeZone: zone),
                zoneID: zone.identifier,
                milliliters: 0,
                dailyGoal: dailyGoal,
                portions: [],
                updatedAt: now
            )
        }
        return self
    }

    var progress: Double {
        min(1, max(0, Double(milliliters) / Double(max(1, dailyGoal))))
    }
}

enum AquaMindWidgetStore {
    static let groupID = "group.com.aquamind.nativehydration"
    static let snapshotKey = "AquaMind.widget.snapshot.v1"

    static func save(_ snapshot: AquaMindWidgetSnapshot) {
        guard let suite = UserDefaults(suiteName: groupID),
              let payload = try? JSONEncoder().encode(snapshot) else { return }
        suite.set(payload, forKey: snapshotKey)
    }

    static func load(now: Date = Date()) -> AquaMindWidgetSnapshot? {
        guard let suite = UserDefaults(suiteName: groupID),
              let payload = suite.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(AquaMindWidgetSnapshot.self, from: payload)
        else { return nil }
        return snapshot.current(on: now)
    }
}
