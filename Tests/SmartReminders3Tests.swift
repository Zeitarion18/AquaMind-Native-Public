import Foundation

/// Pure Foundation regressions for Smart Reminders 3.0.
@main
struct SmartReminders3Tests {
    static func main() {
        var settings = HydrationSettings()
        settings.remindersEnabled = true
        settings.preferredTimeZoneID = "Europe/Samara"
        let cal = settings.calendar
        func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            cal.date(from: DateComponents(timeZone: settings.timeZone,
                year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        }
        let water = WaterEntry(date: date(4, 14, 22), milliliters: 250)
        let now = date(4, 15, 20)

        // Existing 0.7.3 users migrate to the exact balanced 40/40/60 policy.
        assert(settings.reminderStyle == .balanced)
        assert(settings.reminderSoundEnabled)
        assert(settings.snoozeMinutes == 15)
        assert(settings.reminderPauseUntil == nil)
        assert(settings.snoozeUntil == nil)
        let balanced = ReminderPlanner.upcomingDates(
            entries: [water], settings: settings, now: now)
        assert(balanced.prefix(4).map {
            cal.isDate($0, inSameDayAs: water.date)
        }.allSatisfy { $0 })
        assert(balanced[0] == date(4, 15, 37))
        assert(balanced[1] == date(4, 16, 17))
        assert(balanced[2] == date(4, 16, 57))
        assert(balanced[3] == date(4, 17, 57))
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 1, settings: settings) == 40)
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 2, settings: settings) == 40)
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 3, settings: settings) == 60)

        settings.reminderStyle = .gentle
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 1, settings: settings) == 60)
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 3, settings: settings) == 90)
        let gentle = ReminderPlanner.upcomingDates(
            entries: [water], settings: settings, now: now)
        assert(gentle[0] == date(4, 15, 37))
        assert(gentle[1] == date(4, 16, 37))
        assert(gentle[2] == date(4, 17, 37))
        assert(gentle[3] == date(4, 19, 7))

        settings.reminderStyle = .active
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 1, settings: settings) == 30)
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 3, settings: settings) == 45)
        let active = ReminderPlanner.upcomingDates(
            entries: [water], settings: settings, now: now)
        assert(active[0] == date(4, 15, 37))
        assert(active[1] == date(4, 16, 7))
        assert(active[2] == date(4, 16, 37))
        assert(active[3] == date(4, 17, 22))

        // Explicit minimum preference wins even against active mode.
        settings.minimumReminderMinutes = 90
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 1, settings: settings) == 90)
        assert(ReminderPlanner.unloggedFollowUpMinutes(
            afterPreviousCount: 4, settings: settings) == 90)
        settings.minimumReminderMinutes = 30

        // A Snooze persists across all clock refreshes and suppresses regular
        // slots before due + 20 min. It must not alter the drinking logs.
        settings.reminderStyle = .balanced
        settings.snoozeUntil = date(4, 16, 17)
        let deferred = ReminderPlanner.upcomingDates(
            entries: [water], settings: settings, now: now)
        assert(deferred.allSatisfy { $0 > date(4, 16, 37) })
        assert(!deferred.contains(date(4, 15, 37)))
        assert(!deferred.contains(date(4, 16, 17)))
        assert(!deferred.contains(date(4, 16, 37)))
        assert(deferred == ReminderPlanner.upcomingDates(
            entries: [water], settings: settings, now: date(4, 15, 21)),
            "Clock refresh may not reintroduce a dismissed reminder")
        let archive = HydrationArchive(entries: [water], settings: settings)
        let encoded = try! JSONEncoder().encode(archive)
        let restored = try! JSONDecoder().decode(HydrationArchive.self, from: encoded)
        assert(restored.settings.snoozeUntil == settings.snoozeUntil)
        assert(restored.settings.reminderStyle == settings.reminderStyle)
        assert(restored.entries == [water])

        // Long quiet period: every notification before it ends is excluded,
        // including slots reserved for future iOS calendar days.
        settings.snoozeUntil = nil
        settings.reminderPauseUntil = date(5, 9, 0)
        let paused = ReminderPlanner.upcomingDates(
            entries: [water], settings: settings, now: now)
        assert(settings.remindersPaused(at: now))
        assert(paused.allSatisfy { $0 >= settings.reminderPauseUntil! })
        assert(!settings.remindersPaused(at: date(5, 9, 1)))
        assert(paused.count <= ReminderPlanner.notificationLimit)
        assert(zip(paused, paused.dropFirst()).allSatisfy { $0 < $1 })
        settings.reminderPauseUntil = nil
        assert(ReminderPlanner.upcomingDates(
            entries: [water], settings: settings, now: now) == balanced)

        // Sound and Snooze action preference are UI/notification settings,
        // never variables that change the planner's predicted dates.
        settings.reminderSoundEnabled = false
        settings.snoozeMinutes = 30
        assert(ReminderPlanner.upcomingDates(
            entries: [water], settings: settings, now: now) == balanced)
        let silentRestored = try! JSONDecoder().decode(
            HydrationArchive.self,
            from: JSONEncoder().encode(HydrationArchive(
                entries: [water], settings: settings)))
        assert(!silentRestored.settings.reminderSoundEnabled)
        assert(silentRestored.settings.snoozeMinutes == 30)

        // Old archives lacked all 0.7.6 keys and must decode without errors.
        let oldJSON = """
        {"entries":[],"settings":{"dailyGoal":2250,
        "minimumReminderMinutes":45,"adaptiveReminderVersion":1,
        "preferredTimeZoneID":"Europe/Samara"}}
        """
        let old = try! JSONDecoder().decode(
            HydrationArchive.self, from: Data(oldJSON.utf8))
        assert(old.settings.dailyGoal == 2250)
        assert(old.settings.minimumReminderMinutes == 45)
        assert(old.settings.reminderStyle == .balanced)
        assert(old.settings.reminderSoundEnabled)
        assert(old.settings.snoozeMinutes == 15)
        assert(old.settings.snoozeUntil == nil)
        assert(old.settings.reminderPauseUntil == nil)

        // Sleep and completing a goal still override reminder urgency.
        settings.minimumReminderMinutes = 30
        settings.reminderStyle = .active
        settings.sleepStartedAt = date(4, 15, 30)
        settings.sleepPauseUntil = date(5, 6, 30)
        let sleepy = ReminderPlanner.upcomingDates(
            entries: [water], settings: settings, now: now)
        assert(sleepy.allSatisfy { $0 < date(4, 15, 30) ||
                                  $0 >= date(5, 6, 30) })
        settings.sleepStartedAt = nil
        settings.sleepPauseUntil = nil
        settings.dailyGoal = 250
        let completed = ReminderPlanner.upcomingDates(
            entries: [water], settings: settings, now: now)
        assert(!completed.contains { cal.isDate($0, inSameDayAs: water.date) })
        print("AquaMind 0.7.6 passed: three urgency modes, min pause, persisted snooze/pause, silent mode, legacy archive, sleep and goal")
    }
}
