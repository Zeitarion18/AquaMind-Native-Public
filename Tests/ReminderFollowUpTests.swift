import Foundation

/// Regression for 0.7.2: a first alert at 15:37 could be followed by 17:37
/// because it reused a learned 120-minute interval without a new drink.
@main
struct ReminderFollowUpTests {
    static func main() {
        var settings = HydrationSettings()
        settings.remindersEnabled = true
        settings.minimumReminderMinutes = 30
        settings.preferredTimeZoneID = "Europe/Samara"
        let cal = settings.calendar

        func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            cal.date(from: DateComponents(timeZone: settings.timeZone,
                    year: 2026, month: 11, day: day,
                    hour: hour, minute: minute))!
        }

        // 250ml logged at 14:22 -> after the 75-minute volume cooldown
        // the next notification is 15:37, regardless of how often UI refreshes.
        let drink = WaterEntry(date: date(4, 14, 22),
                               milliliters: 250, kind: .water)
        let at1520 = ReminderPlanner.upcomingDates(
            entries: [drink], settings: settings, now: date(4, 15, 20))
        let at1521 = ReminderPlanner.upcomingDates(
            entries: [drink], settings: settings, now: date(4, 15, 21))
        assert(at1520 == at1521, "Clock ticking may not slide pending alerts")

        let afternoon = at1520.filter { cal.isDate($0, inSameDayAs: drink.date) }
        assert(afternoon.count >= 4)
        assert(afternoon[0] == date(4, 15, 37))
        assert(afternoon[1] == date(4, 16, 17),
               "The first unlogged follow-up should be 40 minutes, not two hours")
        assert(afternoon[2] == date(4, 16, 57),
               "The second unlogged follow-up should also be 40 minutes")
        assert(afternoon[3] == date(4, 17, 57),
               "Later alerts should settle to a non-accelerating 60-minute cadence")

        let afterFirst = ReminderPlanner.upcomingDates(
            entries: [drink], settings: settings, now: date(4, 15, 38))
        assert(afterFirst.first == date(4, 16, 17))
        let afterFirstMinute = ReminderPlanner.upcomingDates(
            entries: [drink], settings: settings, now: date(4, 15, 39))
        assert(afterFirst == afterFirstMinute)
        assert(ReminderPlanner.notificationID(for: at1520[1]) ==
               ReminderPlanner.notificationID(for: afterFirst[0]))

        // A *new recorded drink* resets the timer from that entry and
        // triggers a different plan, including the measured 2-hour total.
        let newlyLogged = WaterEntry(date: date(4, 15, 50),
                                     milliliters: 100, kind: .water)
        let withNewDrink = ReminderPlanner.upcomingDates(
            entries: [drink, newlyLogged], settings: settings,
            now: date(4, 15, 51))
        assert(withNewDrink.first == date(4, 17, 25),
               "350ml in two hours should result in a 95-minute cooldown")
        assert(!withNewDrink.contains(date(4, 16, 17)),
               "Obsolete follow-up must be replaced when new intake is logged")

        // Minimum interval preference (set by user) takes precedence.
        settings.minimumReminderMinutes = 90
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 1, settings: settings) == 90)
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 6, settings: settings) == 90)
        let stricter = ReminderPlanner.upcomingDates(
            entries: [drink], settings: settings, now: date(4, 15, 20))
        let strictToday = stricter.filter { cal.isDate($0, inSameDayAs: drink.date) }
        assert(strictToday.count >= 2)
        assert(Int(strictToday[1].timeIntervalSince(strictToday[0]) / 60) == 90)
        settings.minimumReminderMinutes = 30

        // Keep the queue within iOS limits while reserving some upcoming days.
        let limited = ReminderPlanner.upcomingDates(
            entries: [drink], settings: settings, now: date(4, 15, 20))
        assert(limited.count <= ReminderPlanner.notificationLimit)
        assert(Set(limited).count == limited.count)
        assert(zip(limited, limited.dropFirst()).allSatisfy { $0 < $1 })
        for nextDay in 5...10 {
            let day = date(nextDay, 12, 0)
            assert(limited.contains { cal.isDate($0, inSameDayAs: day) },
                   "Reserve at least one future reminder on each of the next 6 days")
        }

        // Quiet hours and a manual sleep override must always win.
        assert(limited.allSatisfy { !ReminderPlanner.isQuietTime(
            settings: settings, now: $0) })
        settings.sleepStartedAt = date(4, 15, 55)
        settings.sleepPauseUntil = ReminderPlanner.nextScheduledWake(
            after: date(4, 15, 55), settings: settings)
        let sleeping = ReminderPlanner.upcomingDates(
            entries: [drink], settings: settings, now: date(4, 16, 0))
        assert(!sleeping.contains { $0 >= date(4, 15, 55) &&
                                    $0 < settings.sleepPauseUntil! })
        assert(!sleeping.isEmpty)
        settings.sleepStartedAt = nil
        settings.sleepPauseUntil = nil

        // Reaching the goal still suppresses all remaining today's alerts.
        settings.dailyGoal = 250
        let completed = ReminderPlanner.upcomingDates(
            entries: [drink], settings: settings, now: date(4, 15, 20))
        assert(!completed.contains { cal.isDate($0, inSameDayAs: drink.date) })
        assert(completed.first != nil)

        print("AquaMind 0.7.3 passed: missed-log 15:37→16:17, stable clocks, cooldown reset, 7-day reserve, sleep and goals")
    }
}
