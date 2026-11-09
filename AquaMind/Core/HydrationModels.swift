import Foundation

enum DrinkKind: String, Codable, CaseIterable, Identifiable {
    case water, tea, coffee, juice, soda, milk, compote, broth, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .water: return "Вода"
        case .tea: return "Чай"
        case .coffee: return "Кофе"
        case .juice: return "Сок"
        case .soda: return "Газировка"
        case .milk: return "Молоко"
        case .compote: return "Компот"
        case .broth: return "Бульон"
        case .other: return "Другое"
        }
    }
}

/// Custom profiles and vessels are local, optional preferences. The historical
/// entry itself keeps a snapshot of name/icon/color so deleting a profile never
/// changes or hides past intake.
struct CustomDrink: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var symbol: String
    var palette: Int
}

struct DrinkVessel: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var milliliters: Int
}

struct DrinkFavorite: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var kind: DrinkKind
    var customDrinkID: UUID?
    var customName: String?
    var milliliters: Int
}

/// Legacy water-only entries don't contain a 'kind' key.
/// Their original id, timestamp and volume are preserved during decoding.
struct WaterEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var milliliters: Int
    var kind: DrinkKind
    var customDrinkName: String? = nil
    /// For entries saved from 0.7.1 onward. Older records retain their name snapshot.
    var customDrinkID: UUID? = nil
    var customDrinkSymbol: String? = nil
    var customDrinkPalette: Int? = nil
    var isEstimated: Bool = false

    init(id: UUID = UUID(), date: Date = Date(),
         milliliters: Int, kind: DrinkKind = .water,
         customDrinkName: String? = nil,
         customDrinkID: UUID? = nil,
         customDrinkSymbol: String? = nil,
         customDrinkPalette: Int? = nil,
         isEstimated: Bool = false) {
        self.id = id
        self.date = date
        self.milliliters = milliliters
        self.kind = kind
        self.customDrinkName = customDrinkName
        self.customDrinkID = customDrinkID
        self.customDrinkSymbol = customDrinkSymbol
        self.customDrinkPalette = customDrinkPalette
        self.isEstimated = isEstimated
    }

    var displayName: String { customDrinkName ?? kind.title }
    var volumeLabel: String { "\(isEstimated ? "≈ " : "")\(milliliters) мл" }

    enum CodingKeys: String, CodingKey {
        case id, date, milliliters, kind, customDrinkName, customDrinkID, customDrinkSymbol, customDrinkPalette, isEstimated
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        milliliters = try values.decode(Int.self, forKey: .milliliters)
        // Only an absent kind is interpreted as old water; malformed types remain visible as data errors.
        kind = try values.decodeIfPresent(DrinkKind.self, forKey: .kind) ?? .water
        customDrinkName = try values.decodeIfPresent(String.self, forKey: .customDrinkName)
        customDrinkID = try values.decodeIfPresent(UUID.self, forKey: .customDrinkID)
        customDrinkSymbol = try values.decodeIfPresent(String.self, forKey: .customDrinkSymbol)
        customDrinkPalette = try values.decodeIfPresent(Int.self, forKey: .customDrinkPalette)
        isEstimated = try values.decodeIfPresent(Bool.self, forKey: .isEstimated) ?? false
    }
}

struct DrinkDaySegment: Identifiable {
    let day: Date
    let kind: DrinkKind
    let milliliters: Int
    var id: String { "\(day.timeIntervalSince1970)-\(kind.rawValue)" }
}

/// Day of the week is Calendar.weekday: Sun=1, Mon=2 ... Sat=7.
struct DaySchedule: Codable, Equatable, Identifiable {
    let weekday: Int
    var wakeMinute: Int
    var sleepMinute: Int

    var id: Int { weekday }

    static let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]
    static let names = ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]

    static func defaultFor(_ weekday: Int) -> DaySchedule {
        // User-configurable suggestions: 06:30 workdays, 11:30 weekends.
        let wake = weekday == 1 || weekday == 7 ? 11 * 60 + 30 : 6 * 60 + 30
        return DaySchedule(weekday: weekday, wakeMinute: wake, sleepMinute: 23 * 60)
    }

    static var defaults: [DaySchedule] {
        orderedWeekdays.map(defaultFor)
    }

    static func timeLabel(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    var label: String { Self.names[max(1, min(7, weekday)) - 1] }
    var wakeLabel: String { Self.timeLabel(wakeMinute) }
    var sleepLabel: String { Self.timeLabel(sleepMinute) }
}

/// User-defined reminder urgency; never a drinking requirement.
enum ReminderStyle: String, Codable, CaseIterable, Identifiable {
    case gentle, balanced, active

    var id: String { rawValue }
    var title: String {
        switch self {
        case .gentle: return "Бережный"
        case .balanced: return "Сбалансированный"
        case .active: return "Активный"
        }
    }
    var firstFollowUpMinutes: Int {
        switch self {
        case .gentle: return 60
        case .balanced: return 40
        case .active: return 30
        }
    }
    var laterFollowUpMinutes: Int {
        switch self {
        case .gentle: return 90
        case .balanced: return 60
        case .active: return 45
        }
    }
}

struct HydrationSettings: Codable, Equatable {
    var dailyGoal: Int = 2000
    var wakeHour: Int = 8
    var sleepHour: Int = 23
    var remindersEnabled: Bool = false
    /// Lower bound for an adaptive pause; never an unconditional 75-minute delay.
    var minimumReminderMinutes: Int = 30
    var preferredTimeZoneID: String = "system"
    var adaptiveReminderVersion: Int = 1
    /// New optional preferences decode safely from legacy hydration.json.
    var reminderStyle: ReminderStyle = .balanced
    var reminderSoundEnabled: Bool = true
    var snoozeMinutes: Int = 15
    /// Only one active explicit Snooze at a time, including after app restarts.
    var snoozeUntil: Date? = nil
    /// Temporary quiet period; unlike sleep it does not move the wake anchor.
    var reminderPauseUntil: Date? = nil

    var weeklySchedule: [DaySchedule] = DaySchedule.defaults
    /// A temporary manual bedtime override, expiring at the next weekly wake time.
    var sleepStartedAt: Date? = nil
    var sleepPauseUntil: Date? = nil
    /// A one-day override for a morning that starts earlier or later than planned.
    var wokeUpAt: Date? = nil

    var customDrinks: [CustomDrink] = []
    var vessels: [DrinkVessel] = []
    var favorites: [DrinkFavorite] = []
    var quickVolumes: [Int] = [150, 250, 350]

    init() {}

    func remindersPaused(at date: Date) -> Bool {
        reminderPauseUntil.map { $0 > date } ?? false
    }

    func snoozeQuietUntil() -> Date? {
        snoozeUntil?.addingTimeInterval(20 * 60)
    }

    func schedule(for weekday: Int) -> DaySchedule {
        weeklySchedule.first(where: { $0.weekday == weekday })
            ?? DaySchedule.defaultFor(weekday)
    }

    func isManualSleepActive(at date: Date) -> Bool {
        guard let started = sleepStartedAt, let until = sleepPauseUntil else {
            return false
        }
        return date >= started && date < until
    }

    enum CodingKeys: String, CodingKey {
        case dailyGoal, wakeHour, sleepHour, remindersEnabled
        case minimumReminderMinutes, preferredTimeZoneID, adaptiveReminderVersion
        case weeklySchedule, sleepStartedAt, sleepPauseUntil, wokeUpAt
        case customDrinks, vessels, favorites, quickVolumes
        case reminderStyle, reminderSoundEnabled, snoozeMinutes
        case snoozeUntil, reminderPauseUntil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dailyGoal = try c.decodeIfPresent(Int.self, forKey: .dailyGoal) ?? 2000
        wakeHour = try c.decodeIfPresent(Int.self, forKey: .wakeHour) ?? 8
        sleepHour = try c.decodeIfPresent(Int.self, forKey: .sleepHour) ?? 23
        remindersEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersEnabled) ?? false
        preferredTimeZoneID = try c.decodeIfPresent(String.self, forKey: .preferredTimeZoneID) ?? "system"

        let previousMinimum = try c.decodeIfPresent(Int.self, forKey: .minimumReminderMinutes) ?? 75
        let previousVersion = try c.decodeIfPresent(Int.self, forKey: .adaptiveReminderVersion) ?? 0
        // Pre-0.4.4 default was 75. Upgrade ONLY that old default to 30.
        // Other prior custom minimum values stay untouched.
        minimumReminderMinutes = previousVersion == 0 && previousMinimum == 75
            ? 30 : min(240, max(30, previousMinimum))
        adaptiveReminderVersion = 1
        reminderStyle = try c.decodeIfPresent(ReminderStyle.self, forKey: .reminderStyle) ?? .balanced
        reminderSoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderSoundEnabled) ?? true
        let previousSnooze = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 15
        snoozeMinutes = [5, 10, 15, 30, 60].contains(previousSnooze) ? previousSnooze : 15
        snoozeUntil = try c.decodeIfPresent(Date.self, forKey: .snoozeUntil)
        reminderPauseUntil = try c.decodeIfPresent(Date.self, forKey: .reminderPauseUntil)

        weeklySchedule = try c.decodeIfPresent([DaySchedule].self,
                                                forKey: .weeklySchedule)
            ?? DaySchedule.defaults
        sleepStartedAt = try c.decodeIfPresent(Date.self, forKey: .sleepStartedAt)
        sleepPauseUntil = try c.decodeIfPresent(Date.self, forKey: .sleepPauseUntil)
        wokeUpAt = try c.decodeIfPresent(Date.self, forKey: .wokeUpAt)
        customDrinks = try c.decodeIfPresent([CustomDrink].self, forKey: .customDrinks) ?? []
        vessels = try c.decodeIfPresent([DrinkVessel].self, forKey: .vessels) ?? []
        favorites = try c.decodeIfPresent([DrinkFavorite].self, forKey: .favorites) ?? []
        let values = try c.decodeIfPresent([Int].self, forKey: .quickVolumes) ?? [150, 250, 350]
        quickVolumes = values.count == 3 && values.allSatisfy({ (25...2000).contains($0) })
            ? values : [150, 250, 350]
    }

    var timeZone: TimeZone {
        if preferredTimeZoneID != "system", let zone = TimeZone(identifier: preferredTimeZoneID) {
            return zone
        }
        return .current
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

struct HydrationArchive: Codable {
    var entries: [WaterEntry] = []
    var settings: HydrationSettings = HydrationSettings()
}

struct DaySummary: Identifiable {
    var day: Date
    var total: Int
    var id: Date { day }
}
