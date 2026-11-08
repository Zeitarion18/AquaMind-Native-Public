import Foundation
import UIKit
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var schedulingTask: Task<Void, Never>?
    @MainActor private var lastPlannedDates: [Date] = []

    private override init() { super.init() }

    func configure() {
        let actions = [
            UNNotificationAction(identifier: "DRANK_150", title: "Выпил 150 мл", options: []),
            UNNotificationAction(identifier: "DRANK_250", title: "Выпил 250 мл", options: []),
            UNNotificationAction(identifier: "DRANK_350", title: "Выпил 350 мл", options: []),
            UNNotificationAction(identifier: "SNOOZE_15", title: "Через 15 мин", options: []),
            UNNotificationAction(identifier: "SNOOZE_60", title: "Через час", options: [])
        ]
        let category = UNNotificationCategory(identifier: "WATER_REMINDER", actions: actions,
                                               intentIdentifiers: [], options: [])
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([category])
    }

    @MainActor
    func schedule(entries: [WaterEntry], settings: HydrationSettings) {
        // Serialize writes instead of canceling a task halfway through deletion.
        // Reopening the app no longer destroys correctly scheduled reminders.
        let previousTask = schedulingTask
        HydrationStore.shared.setReminderQueueStatus(
            settings.remindersEnabled ? .checking : .disabled
        )
        schedulingTask = Task {
            await previousTask?.value

            let center = UNUserNotificationCenter.current()
            let authorization = await center.notificationSettings()
            let existing = await center.pendingNotificationRequests()
            let existingNormal = existing.filter {
                $0.identifier.hasPrefix("am_reminder_")
            }

            if !settings.remindersEnabled {
                center.removePendingNotificationRequests(
                    withIdentifiers: existingNormal.map(\.identifier)
                )
                lastPlannedDates = []
                HydrationStore.shared.setReminderQueueStatus(.disabled)
                return
            }
            guard authorization.authorizationStatus == .authorized ||
                  authorization.authorizationStatus == .provisional else {
                lastPlannedDates = []
                HydrationStore.shared.setReminderQueueStatus(.permissionRequired)
                return
            }

            // Time anchors are independent of every refresh or clock tick.
            let dates = ReminderPlanner.upcomingDates(
                entries: entries, settings: settings, now: Date()
            )
            lastPlannedDates = dates

            let expectedIDs = Set(dates.map(ReminderPlanner.notificationID(for:)))
            let existingByID = Dictionary(
                existingNormal.map { ($0.identifier, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            // Preserve every matching request. Remove only obsolete dates or
            // legacy index-based IDs from older AquaMind versions.
            var removeIDs: [String] = []
            var addDates: [Date] = []
            for request in existingNormal where !expectedIDs.contains(request.identifier) {
                removeIDs.append(request.identifier)
            }
            for date in dates {
                let id = ReminderPlanner.notificationID(for: date)
                if let old = existingByID[id],
                   let next = (old.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
                   abs(next.timeIntervalSince(date)) <= 60 {
                    // Same date is already pending in iOS. Do not touch it.
                    continue
                }
                if existingByID[id] != nil { removeIDs.append(id) }
                addDates.append(date)
            }

            if !removeIDs.isEmpty {
                center.removePendingNotificationRequests(
                    withIdentifiers: Array(Set(removeIDs))
                )
            }

            for date in addDates {
                // The app can stay open while the queue is reconciled.
                // Never insert a calendar trigger for a minute already past.
                guard date > Date().addingTimeInterval(5) else { continue }
                let content = UNMutableNotificationContent()
                content.title = "AquaMind 💧"
                content.body = "Не забывай о воде. Если хочется пить — самое время сделать несколько глотков."
                content.sound = .default
                content.categoryIdentifier = "WATER_REMINDER"
                var components = settings.calendar.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: date
                )
                components.timeZone = settings.timeZone
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: components, repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: ReminderPlanner.notificationID(for: date),
                    content: content, trigger: trigger
                )
                do {
                    try await center.add(request)
                } catch {
                    print("AquaMind: failed to schedule \(date): \(error)")
                }
            }

            HydrationStore.shared.setReminderQueueStatus(
                await readQueueStatus(center: center)
            )
        }
    }

    /// Checks UserNotifications pending requests, rather than just calculating
    /// a theoretical date. Does not reschedule the test notification.
    @MainActor
    func verifyPendingReminders() async -> ReminderQueueStatus {
        await schedulingTask?.value
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings()
        guard authorization.authorizationStatus == .authorized ||
              authorization.authorizationStatus == .provisional else {
            return .permissionRequired
        }
        return await readQueueStatus(center: center)
    }

    @MainActor
    private func readQueueStatus(center: UNUserNotificationCenter) async -> ReminderQueueStatus {
        let requests = await center.pendingNotificationRequests()
        let now = Date()
        let planned = lastPlannedDates.filter { $0 > now.addingTimeInterval(-65) }.sorted()
        let actual = requests.filter { $0.identifier.hasPrefix("am_reminder_") }
            .compactMap { request -> Date? in
                (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            }
            .filter { $0 > now }
            .sorted()
        let delayed = requests.filter { $0.identifier.hasPrefix("am_snooze_") }
            .compactMap { ($0.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() }
            .filter { $0 > now }
            .sorted()

        // An explicit snooze is not a failure of the normal schedule.
        // Show the actual snooze time in the UI.
        if let first = delayed.first, (actual.first == nil || first < actual[0]) {
            return .postponed(next: first)
        }

        if planned.isEmpty && actual.isEmpty {
            return .empty
        }
        // UNCalendarNotificationTrigger stores minute precision, so accept
        // up to 65 seconds difference from an arbitrary-second forecast.
        let agrees = planned.count == actual.count &&
            zip(planned, actual).allSatisfy { abs($0.timeIntervalSince($1)) <= 65 }
        if agrees, let first = actual.first {
            return .confirmed(next: first, count: actual.count)
        }
        return .mismatch(planned: planned.count, queued: actual.count)
    }

    @MainActor
    func snooze(minutes: Int) {
        guard (1...240).contains(minutes) else { return }
        let previousTask = schedulingTask
        schedulingTask = Task {
            await previousTask?.value
            let center = UNUserNotificationCenter.current()
            let due = Date().addingTimeInterval(TimeInterval(minutes * 60))
            let current = await center.pendingNotificationRequests()
            // Snooze should really mean "not before this time".
            let tooEarly = current.filter { request in
                (request.identifier.hasPrefix("am_reminder_") || request.identifier.hasPrefix("am_snooze_")) &&
                ((request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                 ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                 ?? .distantFuture) <= due.addingTimeInterval(20 * 60)
            }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: tooEarly)

            let content = UNMutableNotificationContent()
            content.title = "AquaMind 💧"
            content.body = "Ты просил напомнить о воде чуть позже."
            content.categoryIdentifier = "WATER_REMINDER"
            content.sound = .default
            let request = UNNotificationRequest(identifier: "am_snooze_\(UUID().uuidString)",
                                                content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false))
            do {
                try await center.add(request)
                HydrationStore.shared.setReminderQueueStatus(.postponed(next: due))
            } catch {
                print("AquaMind: snooze scheduling failed: \(error)")
                HydrationStore.shared.setReminderQueueStatus(.mismatch(planned: lastPlannedDates.count, queued: 0))
            }
        }
    }


    /// Diagnostic notification: independent of the normal hydration schedule.
    @MainActor
    func scheduleOneMinuteTest() async throws -> Date {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized ||
              settings.authorizationStatus == .provisional else {
            throw AquaMindTestReminderError.permissionRequired
        }

        let content = UNMutableNotificationContent()
        content.title = "AquaMind 💧"
        content.body = "Тест пройден! AquaMind умеет присылать напоминания."
        content.sound = .default
        content.categoryIdentifier = "WATER_REMINDER"

        // Repeating a test replaces the old pending test.
        let id = "am_test_one_minute"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))

        // Verify iOS really kept the request before displaying success.
        let requests = await center.pendingNotificationRequests()
        guard let request = requests.first(where: { $0.identifier == id }),
              let scheduled = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() else {
            throw AquaMindTestReminderError.notFoundInQueue
        }
        return scheduled
    }

    @MainActor
    func finishPendingChanges() async {
        await schedulingTask?.value
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            switch response.actionIdentifier {
            case "DRANK_150": HydrationStore.shared.add(150)
            case "DRANK_250": HydrationStore.shared.add(250)
            case "DRANK_350": HydrationStore.shared.add(350)
            case "SNOOZE_15": HydrationStore.shared.snooze(minutes: 15)
            case "SNOOZE_60": HydrationStore.shared.snooze(minutes: 60)
            default: break
            }
            // Give iOS time to persist the new notification plan before ending
            // a background notification-action callback.
            await NotificationManager.shared.finishPendingChanges()
            completionHandler()
        }
    }
}

final class AquaMindAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationManager.shared.configure()
        return true
    }
}

private enum AquaMindTestReminderError: LocalizedError {
    case permissionRequired
    case notFoundInQueue

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "Уведомления для AquaMind запрещены. Разреши их в настройках iPhone."
        case .notFoundInQueue:
            return "iPhone не сохранил тестовое уведомление в очереди. Попробуй ещё раз."
        }
    }
}
