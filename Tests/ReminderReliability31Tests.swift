import Foundation

/// Pure Foundation regression checks for Smart Reminders 3.1.
/// Delivery itself still has to be verified on a real iPhone.
@main
struct ReminderReliability31Tests {
    static func main() {
        var settings = HydrationSettings()
        settings.remindersEnabled = true
        settings.preferredTimeZoneID = "Europe/Samara"
        let calendar = settings.calendar

        func day(_ number: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(
                timeZone: settings.timeZone,
                year: 2026, month: 11, day: number,
                hour: hour, minute: minute))!
        }

        let now = day(9, 12, 0)
        assert(ReminderCountdown.message(
            until: now.addingTimeInterval(30), from: now) == "Менее минуты")
        assert(ReminderCountdown.message(
            until: now.addingTimeInterval(24 * 60), from: now) == "Через 24 мин")
        assert(ReminderCountdown.message(
            until: now.addingTimeInterval(80 * 60), from: now) == "Через 1 ч 20 мин")
        assert(ReminderCountdown.message(
            until: now.addingTimeInterval(26 * 3600), from: now) == "Через 1 д 2 ч")
        assert(ReminderCountdown.message(
            until: now.addingTimeInterval(-1), from: now) == "Время наступило")

        let regular = ReminderPlanner.upcomingDates(
            entries: [], settings: settings, now: day(9, 20, 0))
        assert(!regular.isEmpty)
        assert(regular == regular.sorted())
        assert(Set(regular).count == regular.count,
               "Do not create duplicate pending normal dates")
        assert(regular.count <= ReminderPlanner.notificationLimit)

        // A sleeping user must receive no ordinary alert until scheduled wake.
        settings.sleepStartedAt = day(9, 22, 0)
        settings.sleepPauseUntil = day(10, 6, 30)
        let asleep = day(9, 22, 10)
        assert(settings.isManualSleepActive(at: asleep))
        assert(settings.wakeConfirmationPending(at: asleep))
        let duringSleep = ReminderPlanner.upcomingDates(
            entries: [], settings: settings, now: asleep)
        assert(!duringSleep.isEmpty)
        assert(duringSleep.allSatisfy { $0 >= day(10, 6, 30) })

        // Auto-resume does NOT erase the option to confirm an unusually late
        // wake-up. After 24 hours, an abandoned sleep session stops blocking
        // a fresh "Лёг спать" action in the UI.
        let lateWake = day(10, 8, 40)
        assert(!settings.isManualSleepActive(at: lateWake))
        assert(settings.wakeConfirmationPending(at: lateWake))
        assert(!settings.wakeConfirmationPending(at: day(11, 22, 1)))

        // Tapping "Проснулся" uses the real timestamp for today's 30-minute
        // wake anchor, whether the person slept in or woke early.
        settings.sleepStartedAt = nil
        settings.sleepPauseUntil = nil
        settings.wokeUpAt = lateWake
        var future = ReminderPlanner.upcomingDates(
            entries: [], settings: settings, now: day(10, 8, 41))
        assert(future.first == day(10, 9, 10),
               "Late wake must shift the first notification to 30 minutes later")

        settings.wokeUpAt = day(10, 5, 45)
        future = ReminderPlanner.upcomingDates(
            entries: [], settings: settings, now: day(10, 5, 46))
        assert(future.first == day(10, 6, 15),
               "Early wake must also use the actual time, not the old plan")

        // After logging a drink, all future request timestamps must come from
        // a recalculated plan, with no expired request restored.
        settings.wokeUpAt = nil
        let logged = WaterEntry(date: day(10, 11, 0), milliliters: 250)
        future = ReminderPlanner.upcomingDates(
            entries: [logged], settings: settings, now: day(10, 11, 1))
        assert(future.allSatisfy { $0 > day(10, 11, 1) })
        assert(Set(future).count == future.count)

        settings.snoozeUntil = day(10, 12, 0)
        future = ReminderPlanner.upcomingDates(
            entries: [logged], settings: settings, now: day(10, 11, 1))
        assert(future.allSatisfy { $0 > day(10, 12, 20) },
               "Pending normal alerts cannot overlap explicit Snooze protection")

        let queued = [day(10, 9, 10), day(10, 10, 10)]
        assert(NotificationQueueComparison.matches(planned: queued, queued: queued))
        assert(NotificationQueueComparison.matches(
            planned: queued, queued: queued, snoozeCount: 1))
        assert(!NotificationQueueComparison.matches(
            planned: queued, queued: queued, snoozeCount: 2),
               "Two iOS snoozes are a queue integrity problem")
        assert(!NotificationQueueComparison.matches(
            planned: queued,
            queued: [day(10, 9, 10), day(10, 10, 14)]))
        assert(!NotificationQueueComparison.matches(
            planned: queued, queued: [day(10, 9, 10)]))

        print("AquaMind 0.7.9 reliability: countdown, sleep, wake, Snooze, queue dedup and drink regression passed")
    }
}
