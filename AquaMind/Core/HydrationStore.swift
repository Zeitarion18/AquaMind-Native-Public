import Foundation
import Combine
import UserNotifications

enum TestReminderStatus: Equatable {
    case idle
    case scheduling
    case scheduled(Date)
    case failed(String)
}

/// Reflects what UserNotifications actually reports as pending on this iPhone.
enum ReminderQueueStatus: Equatable {
    case disabled
    case checking
    case confirmed(next: Date, count: Int)
    case postponed(next: Date)
    case empty
    case permissionRequired
    case mismatch(planned: Int, queued: Int)
}

@MainActor
final class HydrationStore: ObservableObject {
    static let shared = HydrationStore()

    @Published private(set) var entries: [WaterEntry] = []
    @Published private(set) var settings = HydrationSettings()
    @Published private(set) var selectedDrink: DrinkKind =
        DrinkKind(rawValue: UserDefaults.standard.string(forKey: "AquaMind.selectedDrink") ?? "") ?? .water
    @Published private(set) var selectedCustomDrinkID: UUID? = {
        guard let raw = UserDefaults.standard.string(forKey: "AquaMind.selectedCustomDrink"),
              let id = UUID(uuidString: raw) else { return nil }
        return id
    }()
    @Published private(set) var notificationsAllowed = false
    @Published private(set) var testReminderStatus: TestReminderStatus = .idle
    @Published private(set) var reminderQueueStatus: ReminderQueueStatus = .checking
    @Published private(set) var storageIssue: String?

    private let archiveURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = support.appendingPathComponent("AquaMind", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        archiveURL = folder.appendingPathComponent("hydration.json")

        do {
            let data = try Data(contentsOf: archiveURL)
            let decoded = try JSONDecoder().decode(HydrationArchive.self, from: data)
            entries = decoded.entries
            settings = decoded.settings
        } catch {
            if FileManager.default.fileExists(atPath: archiveURL.path) {
                storageIssue = "Не удалось прочитать сохранённую историю. Файл не перезаписан."
            }
        }
    }

    var todayTotal: Int {
        ReminderPlanner.dailyTotal(entries: entries, on: Date(), calendar: settings.calendar)
    }

    var todayEntries: [WaterEntry] {
        entries.filter { settings.calendar.isDate($0.date, inSameDayAs: Date()) }
            .sorted { $0.date > $1.date }
    }


    var todayBreakdown: [(identity: AnalyticsDrinkIdentity, amount: Int)] {
        HydrationRing.breakdown(entries: todayEntries, profiles: settings.customDrinks)
    }

    var weeklySegments: [DrinkDaySegment] {
        lastSevenDays.flatMap { summary in
            DrinkKind.allCases.compactMap { kind in
                let sum = entries.filter {
                    $0.kind == kind && settings.calendar.isDate($0.date, inSameDayAs: summary.day)
                }.reduce(0) { $0 + $1.milliliters }
                return sum > 0 ? DrinkDaySegment(day: summary.day, kind: kind, milliliters: sum) : nil
            }
        }
    }

    var progress: Double {
        min(1, Double(todayTotal) / Double(max(1, settings.dailyGoal)))
    }

    /// Matches the day and categories of the drink breakdown below the ring.
    var ringSegments: [HydrationRingSlice] {
        HydrationRing.segments(entries: todayEntries, goal: settings.dailyGoal,
                               profiles: settings.customDrinks)
    }

    var lastSevenDays: [DaySummary] {
        let cal = settings.calendar
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { n in
            guard let day = cal.date(byAdding: .day, value: -n, to: today) else { return nil }
            return DaySummary(day: day, total: ReminderPlanner.dailyTotal(entries: entries, on: day, calendar: cal))
        }
    }

    var historyDays: [DaySummary] {
        let cal = settings.calendar
        let days = Set(entries.map { cal.startOfDay(for: $0.date) })
        return days.sorted(by: >).map { day in
            DaySummary(day: day, total: ReminderPlanner.dailyTotal(entries: entries, on: day, calendar: cal))
        }
    }

    func entries(on day: Date) -> [WaterEntry] {
        entries.filter { settings.calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    var activeCustomDrink: CustomDrink? {
        guard let id = selectedCustomDrinkID else { return nil }
        return settings.customDrinks.first { $0.id == id }
    }

    var selectedDrinkTitle: String {
        activeCustomDrink?.name ?? selectedDrink.title
    }

    func selectDrink(_ kind: DrinkKind) {
        selectedCustomDrinkID = nil
        UserDefaults.standard.removeObject(forKey: "AquaMind.selectedCustomDrink")
        selectedDrink = kind
        UserDefaults.standard.set(kind.rawValue, forKey: "AquaMind.selectedDrink")
    }

    func selectCustomDrink(_ id: UUID) {
        guard settings.customDrinks.contains(where: { $0.id == id }) else { return }
        selectedCustomDrinkID = id
        selectedDrink = .other
        UserDefaults.standard.set("other", forKey: "AquaMind.selectedDrink")
        UserDefaults.standard.set(id.uuidString, forKey: "AquaMind.selectedCustomDrink")
    }

    /// Main-screen personal drink selection. Notification actions continue
    /// calling add(ml) and always record plain water.
    func addSelected(_ ml: Int, estimated: Bool = false) {
        guard (25...2000).contains(ml) else { return }
        if let custom = activeCustomDrink {
            entries.append(WaterEntry(milliliters: ml, kind: .other,
                                      customDrinkName: custom.name,
                                      customDrinkID: custom.id,
                                      customDrinkSymbol: custom.symbol,
                                      customDrinkPalette: custom.palette,
                                      isEstimated: estimated))
        } else {
            entries.append(WaterEntry(milliliters: ml, kind: selectedDrink,
                                      isEstimated: estimated))
        }
        settings.snoozeUntil = nil
        commit()
    }

    func saveCustomDrink(_ draft: CustomDrink) {
        let name = String(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        guard !name.isEmpty else { return }
        let item = CustomDrink(id: draft.id, name: name,
                               symbol: DrinkIconCatalog.isSupported(draft.symbol)
                                   ? draft.symbol : "drop.fill",
                               palette: max(0, min(PersonalDrinkPalette.choices.count - 1,
                                                   draft.palette)))
        if let index = settings.customDrinks.firstIndex(where: { $0.id == item.id }) {
            settings.customDrinks[index] = item
        } else {
            guard settings.customDrinks.count < 30 else { return }
            settings.customDrinks.append(item)
        }
        commit()
    }

    func deleteCustomDrink(_ id: UUID) {
        settings.customDrinks.removeAll { $0.id == id }
        settings.favorites.removeAll { $0.customDrinkID == id }
        if selectedCustomDrinkID == id { selectDrink(.water) }
        commit()
    }

    func saveVessel(_ draft: DrinkVessel) {
        let name = String(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32))
        guard !name.isEmpty, (25...2000).contains(draft.milliliters) else { return }
        let vessel = DrinkVessel(id: draft.id, name: name, milliliters: draft.milliliters)
        if let index = settings.vessels.firstIndex(where: { $0.id == vessel.id }) {
            settings.vessels[index] = vessel
        } else {
            guard settings.vessels.count < 20 else { return }
            settings.vessels.append(vessel)
        }
        commit()
    }

    func deleteVessel(_ id: UUID) {
        settings.vessels.removeAll { $0.id == id }
        commit()
    }

    func setQuickVolume(at index: Int, milliliters: Int) {
        guard (0..<3).contains(index), (25...2000).contains(milliliters) else { return }
        settings.quickVolumes[index] = milliliters
        commit()
    }

    func saveFavoriteForSelection(_ milliliters: Int) {
        guard (25...2000).contains(milliliters), settings.favorites.count < 8 else { return }
        let item = DrinkFavorite(kind: selectedDrink,
                                 customDrinkID: activeCustomDrink?.id,
                                 customName: activeCustomDrink?.name,
                                 milliliters: milliliters)
        guard !settings.favorites.contains(where: {
            $0.kind == item.kind && $0.customDrinkID == item.customDrinkID &&
            $0.milliliters == item.milliliters
        }) else { return }
        settings.favorites.append(item)
        commit()
    }

    func deleteFavorite(_ id: UUID) {
        settings.favorites.removeAll { $0.id == id }
        commit()
    }

    func addFavorite(_ item: DrinkFavorite) {
        if let id = item.customDrinkID,
           settings.customDrinks.contains(where: { $0.id == id }) {
            selectCustomDrink(id)
        } else {
            selectDrink(item.kind)
        }
        addSelected(item.milliliters)
    }

    /// Default water is important: the existing iPhone/Watch notification actions
    /// must never silently log coffee or tea based on the open screen selection.
    func add(_ ml: Int, kind: DrinkKind = .water) {
        guard (25...2000).contains(ml) else { return }
        entries.append(WaterEntry(milliliters: ml, kind: kind))
        settings.snoozeUntil = nil
        commit()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        commit()
    }

    func setGoal(_ value: Int) {
        settings.dailyGoal = min(5000, max(250, value))
        commit()
    }

    func setDaySchedule(weekday: Int, wakeMinute: Int? = nil,
                        sleepMinute: Int? = nil) {
        guard (1...7).contains(weekday) else { return }
        var edited = settings.schedule(for: weekday)
        if let wakeMinute = wakeMinute {
            edited.wakeMinute = max(0, min(1439, wakeMinute))
        }
        if let sleepMinute = sleepMinute {
            edited.sleepMinute = max(0, min(1439, sleepMinute))
        }
        settings.weeklySchedule.removeAll { $0.weekday == weekday }
        settings.weeklySchedule.append(edited)
        settings.weeklySchedule.sort {
            DaySchedule.orderedWeekdays.firstIndex(of: $0.weekday)! <
            DaySchedule.orderedWeekdays.firstIndex(of: $1.weekday)!
        }
        commit()
    }

    /// Called from the app or the corresponding Shortcuts action.
    func beginSleep() {
        let now = Date()
        settings.snoozeUntil = nil
        settings.sleepStartedAt = now
        settings.sleepPauseUntil = ReminderPlanner.nextScheduledWake(
            after: now, settings: settings
        )
        settings.wokeUpAt = nil
        commit()
    }

    /// Early or late wake-up affects only today's scheduled wake time.
    func wakeUp() {
        settings.sleepStartedAt = nil
        settings.sleepPauseUntil = nil
        settings.wokeUpAt = Date()
        commit()
    }

    func setMinimumReminderMinutes(_ value: Int) {
        settings.minimumReminderMinutes = min(240, max(30, value))
        settings.adaptiveReminderVersion = 1
        commit()
    }

    func setReminderStyle(_ style: ReminderStyle) {
        settings.reminderStyle = style
        commit()
    }

    func setReminderSound(_ enabled: Bool) {
        settings.reminderSoundEnabled = enabled
        commit()
    }

    func setSnoozeMinutes(_ value: Int) {
        guard [5, 10, 15, 30, 60].contains(value) else { return }
        settings.snoozeMinutes = value
        commit()
    }

    func pauseReminders(minutes: Int) {
        guard settings.remindersEnabled, [30, 60, 120].contains(minutes) else { return }
        settings.reminderPauseUntil = Date().addingTimeInterval(Double(minutes * 60))
        settings.snoozeUntil = nil
        commit()
    }

    func pauseUntilNextWake() {
        guard settings.remindersEnabled else { return }
        settings.reminderPauseUntil = ReminderPlanner.nextScheduledWake(
            after: Date(), settings: settings
        )
        settings.snoozeUntil = nil
        commit()
    }

    func resumeReminders() {
        settings.reminderPauseUntil = nil
        commit()
    }

    func setTimeZone(_ value: String) {
        settings.preferredTimeZoneID = value
        commit()
    }

    func setReminders(_ enabled: Bool) {
        guard enabled else {
            settings.remindersEnabled = false
            settings.snoozeUntil = nil
            settings.reminderPauseUntil = nil
            commit()
            return
        }
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                notificationsAllowed = granted
                settings.remindersEnabled = granted
                commit()
            } catch {
                notificationsAllowed = false
                settings.remindersEnabled = false
                commit()
            }
        }
    }

    func refresh() {
        AquaMindWidgetSync.update(entries: entries, settings: settings)
        Task {
            let state = await UNUserNotificationCenter.current().notificationSettings()
            notificationsAllowed = state.authorizationStatus == .authorized || state.authorizationStatus == .provisional
            if !settings.remindersEnabled {
                reminderQueueStatus = .disabled
            } else if !notificationsAllowed {
                reminderQueueStatus = .permissionRequired
            } else {
                NotificationManager.shared.schedule(entries: entries, settings: settings)
            }
        }
    }

    func setReminderQueueStatus(_ status: ReminderQueueStatus) {
        reminderQueueStatus = status
    }

    func verifyPendingReminders() {
        guard settings.remindersEnabled else {
            reminderQueueStatus = .disabled
            return
        }
        reminderQueueStatus = .checking
        Task {
            reminderQueueStatus = await NotificationManager.shared.verifyPendingReminders()
        }
    }

    /// Snooze is recorded in the archive before the iOS queue is rebuilt,
    /// preventing any early regular reminder from coming back on refresh.
    func snooze(minutes: Int) {
        guard (1...240).contains(minutes), settings.remindersEnabled else { return }
        let now = Date()
        let requested = now.addingTimeInterval(Double(minutes * 60))
        let due: Date
        if ReminderPlanner.isQuietTime(settings: settings, now: requested) {
            due = ReminderPlanner.nextScheduledWake(after: requested,
                                                    settings: settings)
                .addingTimeInterval(30 * 60)
        } else {
            due = requested
        }
        settings.snoozeUntil = due
        settings.reminderPauseUntil = nil
        commit()
    }

    /// Widget links open the host application and log exactly one water entry.
    /// Only our own custom URL scheme and three fixed amounts are accepted.
    func handleWidgetURL(_ url: URL) {
        guard url.scheme?.lowercased() == "aquamind" else { return }
        guard url.host?.lowercased() == "add" else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let text = query?.queryItems?.first(where: { $0.name == "amount" })?.value,
              let amount = Int(text), [150, 250, 350].contains(amount) else { return }
        add(amount, kind: .water)
    }

    func scheduleTestReminder() {
        guard testReminderStatus != .scheduling else { return }
        testReminderStatus = .scheduling
        Task {
            do {
                let due = try await NotificationManager.shared.scheduleOneMinuteTest()
                testReminderStatus = .scheduled(due)
            } catch {
                testReminderStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func commit() {
        guard storageIssue == nil else { return }
        let archive = HydrationArchive(entries: entries, settings: settings)
        do {
            let data = try JSONEncoder().encode(archive)
            try data.write(to: archiveURL, options: .atomic)
            AquaMindWidgetSync.update(entries: entries, settings: settings)
            NotificationManager.shared.schedule(entries: entries, settings: settings)
        } catch {
            storageIssue = "Не удалось сохранить данные: \(error.localizedDescription)"
        }
    }
}
