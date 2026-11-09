import Foundation

/// Rules are intentionally transparent, gentle and entirely local.
/// They estimate when to offer another drink; they are not a medical prescription.
enum ReminderPlanner {
    static let notificationLimit = 58 // iOS allows 64 pending requests; leave room for tests/snoozes.
    static let recentWindowMinutes = 120

    /// Short reminders after a scheduled alert that was not followed by a
    /// drink entry. This models *no new log*, NOT notification delivery/read.
    // Balanced defaults are the exact 0.7.3 cadence.
    static let firstUnloggedFollowUpMinutes = 40
    static let continuedUnloggedFollowUpMinutes = 60
    /// Keep room for mornings on subsequent days in iOS's 64-request queue.
    static let reservedFutureDays = 7

    static func unloggedFollowUpMinutes(afterPreviousCount count: Int,
                                        settings: HydrationSettings) -> Int {
        // Honor the user's explicit "not more often than" setting.
        max(settings.minimumReminderMinutes,
            count <= 2 ? settings.reminderStyle.firstFollowUpMinutes :
                         settings.reminderStyle.laterFollowUpMinutes)
    }

    /// Local notifications keep stable identifiers for the same absolute minute.
    /// Unlike position-based IDs, refilling the future schedule never replaces
    /// a still-valid notification that has not yet fired.
    static func notificationID(for date: Date) -> String {
        "am_reminder_\(Int(date.timeIntervalSince1970 / 60))"
    }

    /// One awake window for a given calendar day. If bedtime is earlier
    /// than wake time, it belongs to the following day (e.g. 01:00).
    static func awakeWindow(for day: Date, settings: HydrationSettings) -> DateInterval? {
        let cal = settings.calendar
        let weekday = cal.component(.weekday, from: day)
        let schedule = settings.schedule(for: weekday)
        let wakeHour = schedule.wakeMinute / 60
        let wakeMinute = schedule.wakeMinute % 60
        let sleepHour = schedule.sleepMinute / 60
        let sleepMinute = schedule.sleepMinute % 60

        guard var start = cal.date(bySettingHour: wakeHour, minute: wakeMinute,
                                    second: 0, of: day),
              var end = cal.date(bySettingHour: sleepHour, minute: sleepMinute,
                                  second: 0, of: day) else { return nil }
        if end <= start {
            guard let next = cal.date(byAdding: .day, value: 1, to: end) else { return nil }
            end = next
        }

        // "Проснулся" overrides only its calendar day, never next week's schedule.
        if let actualWake = settings.wokeUpAt,
           cal.isDate(actualWake, inSameDayAs: day),
           actualWake < end {
            start = actualWake
        }

        // "Лёг спать" stops the current window immediately.
        if let began = settings.sleepStartedAt, let until = settings.sleepPauseUntil,
           until > began, began >= start && began < end {
            end = began
        }
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    static func nextScheduledWake(after moment: Date,
                                  settings: HydrationSettings) -> Date {
        let cal = settings.calendar
        let today = cal.startOfDay(for: moment)
        for offset in 0..<9 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else {
                continue
            }
            let schedule = settings.schedule(for: cal.component(.weekday, from: day))
            if let start = cal.date(bySettingHour: schedule.wakeMinute / 60,
                                    minute: schedule.wakeMinute % 60, second: 0, of: day),
               start > moment {
                return start
            }
        }
        // Defensive fallback if the time zone has unusual calendar anomalies.
        return moment.addingTimeInterval(12 * 3600)
    }

    static func isQuietTime(settings: HydrationSettings, now: Date) -> Bool {
        if settings.isManualSleepActive(at: now) { return true }
        let cal = settings.calendar
        let day = cal.startOfDay(for: now)
        if let current = awakeWindow(for: day, settings: settings),
           current.contains(now) { return false }
        if let previousDay = cal.date(byAdding: .day, value: -1, to: day),
           let previous = awakeWindow(for: previousDay, settings: settings),
           previous.contains(now) { return false }
        return true
    }

    struct ReminderInsight {
        let next: Date?
        let headline: String
        let explanation: String
        let recentMilliliters: Int
        let todayMilliliters: Int
        let recommendedPauseMinutes: Int?
        let learnedMinutes: Int?
    }

    static func dailyTotal(entries: [WaterEntry], on day: Date, calendar: Calendar) -> Int {
        entries.filter { calendar.isDate($0.date, inSameDayAs: day) }
            .reduce(0) { $0 + max(0, $1.milliliters) }
    }

    /// Two-hour intake leading up to the last drink, not merely the last event.
    /// This keeps clustered drinks from triggering a premature new reminder.
    static func recentVolume(entries: [WaterEntry], through moment: Date, calendar: Calendar) -> Int {
        let cutoff = moment.addingTimeInterval(-Double(recentWindowMinutes) * 60)
        return entries.filter {
            $0.date >= cutoff && $0.date <= moment && calendar.isDate($0.date, inSameDayAs: moment)
        }.reduce(0) { $0 + max(0, $1.milliliters) }
    }

    /// Gentle adaptive reminders based on the amount logged recently.
    /// These are notification intervals, not instructions to drink that often.
    /// The 2-hour sum prevents a new 50ml entry from ignoring an earlier glass.
    static func intervalMinutes(after amount: Int, minimum: Int) -> Int {
        let volume = max(0, amount)
        let suggested: Int
        switch volume {
        case ..<75: suggested = 30    // only a few sips
        case ..<125: suggested = 40
        case ..<225: suggested = 55
        case ..<325: suggested = 75
        case ..<450: suggested = 95
        case ..<600: suggested = 120
        case ..<800: suggested = 140
        default: suggested = 165
        }
        return max(minimum, suggested)
    }

    /// Uses intervals between distinct drinking sessions on previous seven days.
    /// Brief bursts (<45 minutes) are one session and are ignored for learning.
    /// Without history, subsequent reminders use a gentle 75-minute cadence.
    /// Historical median, maintained as a fallback for users without enough
    /// separate workday/weekend examples. A session is a pair of records
    /// 45–240 minutes apart on the same calendar day.
    static func learnedIntervalMinutes(entries: [WaterEntry],
                                       settings: HydrationSettings, now: Date) -> Int? {
        let cal = settings.calendar
        let startToday = cal.startOfDay(for: now)
        guard let beginning = cal.date(byAdding: .day, value: -7, to: startToday) else { return nil }
        let history = entries.filter {
            $0.date >= beginning && $0.date < startToday
        }.sorted { $0.date < $1.date }
        guard history.count >= 4 else { return nil }
        var gaps: [Int] = []
        for (lhs, rhs) in zip(history, history.dropFirst()) {
            guard cal.isDate(lhs.date, inSameDayAs: rhs.date) else { continue }
            let minutes = Int(rhs.date.timeIntervalSince(lhs.date) / 60)
            if (45...240).contains(minutes) { gaps.append(minutes) }
        }
        guard gaps.count >= 3 else { return nil }
        gaps.sort()
        return min(150, max(90, gaps[gaps.count / 2]))
    }

    static func isWeekend(_ day: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: day)
        return weekday == 1 || weekday == 7
    }

    /// 28-day lookback: weekends have far fewer days available for learning.
    /// Require at least three valid gaps across two *different* days, rather
    /// than mistaking a single unusually busy day for a lasting habit.
    static func learnedIntervalForDayType(entries: [WaterEntry],
                                          settings: HydrationSettings,
                                          day: Date) -> Int? {
        let cal = settings.calendar
        let targetWeekend = isWeekend(day, calendar: cal)
        let startOfTarget = cal.startOfDay(for: day)
        guard let start = cal.date(byAdding: .day, value: -28,
                                   to: startOfTarget) else { return nil }
        let history = entries.filter {
            $0.date >= start && $0.date < startOfTarget &&
            isWeekend($0.date, calendar: cal) == targetWeekend
        }.sorted { $0.date < $1.date }
        var gaps: [Int] = []
        var sampleDays: Set<Date> = []
        for (lhs, rhs) in zip(history, history.dropFirst()) {
            guard cal.isDate(lhs.date, inSameDayAs: rhs.date) else { continue }
            let minutes = Int(rhs.date.timeIntervalSince(lhs.date) / 60)
            guard (45...240).contains(minutes) else { continue }
            gaps.append(minutes)
            sampleDays.insert(cal.startOfDay(for: lhs.date))
        }
        guard gaps.count >= 3, sampleDays.count >= 2 else { return nil }
        gaps.sort()
        return min(150, max(75, gaps[gaps.count / 2]))
    }

    static func habitSummary(entries: [WaterEntry],
                             settings: HydrationSettings, day: Date) -> String {
        let weekend = isWeekend(day, calendar: settings.calendar)
        if let typed = learnedIntervalForDayType(entries: entries,
                                                 settings: settings, day: day) {
            let type = weekend ? "выходных" : "будней"
            return "Учитываю записи прошлых \(type): привычный интервал около \(typed) мин."
        }
        if let generic = learnedIntervalMinutes(entries: entries, settings: settings, now: day) {
            return "Для отдельных \(weekend ? "выходных" : "будней") пока мало записей. Использую общий привычный интервал около \(generic) мин."
        }
        return "Записей ещё мало для надёжного определения привычек \(weekend ? "выходных" : "будней"). Пока используется спокойный стандартный ритм."
    }

    static func repeatMinutes(entries: [WaterEntry], settings: HydrationSettings,
                              now: Date) -> Int {
        // Never chase the goal with progressively shorter reminders.
        let specialized = learnedIntervalForDayType(entries: entries, settings: settings, day: now)
        let fallback = learnedIntervalMinutes(entries: entries, settings: settings, now: now)
        let preference = specialized ?? fallback ?? 75
        return max(settings.minimumReminderMinutes, 75, min(120, preference))
    }

    /// The next reminder after an actual drink is calculated using *all* liquids
    /// recorded in the preceding two hours. More logged intake -> longer pause.
    static func cooldownMinutes(dayEntries: [WaterEntry],
                                settings: HydrationSettings) -> Int? {
        guard let last = dayEntries.max(by: { $0.date < $1.date }) else { return nil }
        let total = recentVolume(entries: dayEntries, through: last.date, calendar: settings.calendar)
        let dayTotal = dayEntries.reduce(0) { $0 + max(0, $1.milliliters) }
        let goalFraction = Double(dayTotal) / Double(max(1, settings.dailyGoal))
        let extraNearGoal = goalFraction >= 0.80 ? 20 : 0
        return min(210, intervalMinutes(after: total, minimum: settings.minimumReminderMinutes) + extraNearGoal)
    }

    static func upcomingDates(entries: [WaterEntry],
                              settings: HydrationSettings, now: Date = Date()) -> [Date] {
        guard settings.remindersEnabled else { return [] }
        let cal = settings.calendar
        let today = cal.startOfDay(for: now)
        var allCandidates: [Date] = []
        var firstOfUpcomingDays: [Date] = []
        // Persisted fences prevent scheduled reminders from returning after
        // app restart or a drink log during explicit Pause or Snooze.
        let pauseEnd = settings.reminderPauseUntil ?? .distantPast
        let snoozeQuietEnd = settings.snoozeQuietUntil() ?? .distantPast

        // Generate candidates independently of clock-refresh timing.
        // A logged drink determines the first alert; after that, we can
        // schedule closer follow-ups in advance without observing delivery.
        // As soon as a new drink is logged, the queue is reconciled.
        for offset in 0..<15 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today),
                  let window = awakeWindow(for: day, settings: settings) else {
                continue
            }
            let awake = window.start
            let bedtime = window.end
            if dailyTotal(entries: entries, on: day, calendar: cal) >= settings.dailyGoal {
                continue
            }

            let dayEntries = entries.filter {
                cal.isDate($0.date, inSameDayAs: day) && $0.date <= now
            }
            let isOverrideWake = settings.wokeUpAt.map {
                cal.isDate($0, inSameDayAs: day)
            } ?? false
            var next = awake.addingTimeInterval(isOverrideWake ? 30 * 60 : 60 * 60)

            if offset == 0,
               let last = dayEntries.max(by: { $0.date < $1.date }),
               let pause = cooldownMinutes(dayEntries: dayEntries, settings: settings) {
                // Stable absolute anchor after a drink, not Date() + a pause.
                next = max(next, last.date.addingTimeInterval(Double(pause) * 60))
            }

            // Match the minute-based UNCalendarNotificationTrigger precisely.
            next = cal.date(from: cal.dateComponents(
                [.year, .month, .day, .hour, .minute], from: next)) ?? next

            var followUpCount = 0
            var firstForThisDay: Date?
            while next < bedtime.addingTimeInterval(-30 * 60) {
                let sleeping = settings.sleepStartedAt.map { started in
                    next >= started && next < (settings.sleepPauseUntil ?? started)
                } ?? false
                if next > now.addingTimeInterval(5) &&
                   next >= pauseEnd && next > snoozeQuietEnd && !sleeping {
                    allCandidates.append(next)
                    if firstForThisDay == nil { firstForThisDay = next }
                }

                // The first two follow-ups follow the selected urgency,
                // later alerts calm down. User minimum is always respected.
                followUpCount += 1
                let pause = unloggedFollowUpMinutes(
                    afterPreviousCount: followUpCount, settings: settings)
                next = next.addingTimeInterval(Double(pause) * 60)
            }

            if offset < reservedFutureDays, let firstForThisDay {
                firstOfUpcomingDays.append(firstForThisDay)
            }
        }

        // iOS accepts at most 64 pending local notifications (we use 58
        // to keep room for Snooze and tests). A 40-minute interval could
        // exhaust those slots in two or three days if we filled greedily.
        // Reserve one morning anchor per day for the coming week, then
        // fill the remaining slots chronologically with closer follow-ups.
        let protected = Set(firstOfUpcomingDays)
        var selected = firstOfUpcomingDays
        for date in allCandidates.sorted() {
            guard selected.count < notificationLimit else { break }
            if !protected.contains(date) {
                selected.append(date)
            }
        }
        return selected.sorted()
    }

    static func insight(entries: [WaterEntry],
                        settings: HydrationSettings, now: Date = Date()) -> ReminderInsight {
        let cal = settings.calendar
        let total = dailyTotal(entries: entries, on: now, calendar: cal)
        let recent = recentVolume(entries: entries, through: now, calendar: cal)
        let learned = learnedIntervalForDayType(entries: entries, settings: settings, day: now)
            ?? learnedIntervalMinutes(entries: entries, settings: settings, now: now)

        guard settings.remindersEnabled else {
            return ReminderInsight(next: nil, headline: "Напоминания выключены",
                explanation: "Включи их в настройках, чтобы AquaMind предложил удобный интервал.",
                recentMilliliters: recent, todayMilliliters: total,
                recommendedPauseMinutes: nil, learnedMinutes: learned)
        }

        let upcoming = upcomingDates(entries: entries, settings: settings, now: now)
        guard let next = upcoming.first else {
            let text = total >= settings.dailyGoal
                ? "Дневная цель уже отмечена. До следующего дня новых напоминаний нет."
                : "В выбранном расписании ближайших напоминаний сейчас нет."
            return ReminderInsight(next: nil, headline: "Пока без напоминаний",
                explanation: text, recentMilliliters: recent, todayMilliliters: total,
                recommendedPauseMinutes: nil, learnedMinutes: learned)
        }

        if settings.remindersPaused(at: now) {
            return ReminderInsight(next: next, headline: "Напоминания на паузе",
                explanation: "Ты временно приостановил уведомления. Они продолжатся после окончания паузы по обычному расписанию.",
                recentMilliliters: recent, todayMilliliters: total,
                recommendedPauseMinutes: nil, learnedMinutes: learned)
        }

        if let due = settings.snoozeUntil, due > now {
            return ReminderInsight(next: due, headline: "Отложено по твоему запросу",
                explanation: "До выбранного времени AquaMind не отправляет обычные повторы. После него действует защитный интервал в 20 минут.",
                recentMilliliters: recent, todayMilliliters: total,
                recommendedPauseMinutes: nil, learnedMinutes: learned)
        }

        if total >= settings.dailyGoal {
            return ReminderInsight(next: next, headline: "Сегодня цель достигнута",
                explanation: "На сегодня напоминания приостановлены. Следующий день начнётся по твоему расписанию.",
                recentMilliliters: recent, todayMilliliters: total,
                recommendedPauseMinutes: nil, learnedMinutes: learned)
        }

        if isQuietTime(settings: settings, now: now) {
            let manual = settings.isManualSleepActive(at: now)
            return ReminderInsight(next: next,
                headline: manual ? "Пауза на сон" : "Ночной режим",
                explanation: manual
                    ? "Ты включил режим сна. Напоминания приостановлены до подъёма или указанного времени пробуждения."
                    : "Сейчас время отдыха. AquaMind не будет беспокоить тебя до утра. Первое напоминание придёт по твоему расписанию.",
                recentMilliliters: recent, todayMilliliters: total,
                recommendedPauseMinutes: nil, learnedMinutes: learned)
        }
        guard cal.isDate(next, inSameDayAs: now) else {
            return ReminderInsight(next: next, headline: "На сегодня уведомления закончились",
                explanation: "Следующее напоминание запланировано на другой день. Ночью AquaMind не беспокоит.",
                recentMilliliters: recent, todayMilliliters: total,
                recommendedPauseMinutes: nil, learnedMinutes: learned)
        }

        let dayEntries = entries.filter {
            cal.isDate($0.date, inSameDayAs: now) && $0.date <= now
        }
        if let last = dayEntries.max(by: { $0.date < $1.date }),
           let pause = cooldownMinutes(dayEntries: dayEntries, settings: settings) {
            let clustered = recentVolume(entries: dayEntries, through: last.date, calendar: cal)
            let nearGoal = Double(total) / Double(max(1, settings.dailyGoal)) >= 0.80
            var detail = "За два часа перед последней записью учтено \(clustered) мл. Следующая пауза — \(pause) мин. Чем меньше объём, тем короче пауза."
            if nearGoal { detail += " Цель почти выполнена, поэтому пауза длиннее." }
            detail += " Если новой записи после уведомления нет, первые повторы идут через \(unloggedFollowUpMinutes(afterPreviousCount: 1, settings: settings)) минут, затем реже."
            detail += " " + habitSummary(entries: entries, settings: settings, day: now)
            return ReminderInsight(next: next,
                headline: clustered > last.milliliters ? "Учтено несколько напитков" : "Пауза после напитка",
                explanation: detail,
                recentMilliliters: recent, todayMilliliters: total,
                recommendedPauseMinutes: pause, learnedMinutes: learned)
        }

        let msg = "Если напиток не записан, AquaMind сначала напомнит повторно через \(unloggedFollowUpMinutes(afterPreviousCount: 1, settings: settings)) минут, затем перейдёт к спокойному ритму. " +
            habitSummary(entries: entries, settings: settings, day: now)
        return ReminderInsight(next: next, headline: "Спокойное напоминание",
            explanation: msg, recentMilliliters: recent, todayMilliliters: total,
            recommendedPauseMinutes: unloggedFollowUpMinutes(afterPreviousCount: 1,
                                                             settings: settings),
            learnedMinutes: learned)
    }
}

/// Checks that pending iOS calendar triggers match the already-fixed plan.
/// The system normalizes calendar seconds, hence the 65-second tolerance.
enum NotificationQueueComparison {
    static func matches(planned: [Date], queued: [Date]) -> Bool {
        guard planned.count == queued.count else { return false }
        return zip(planned.sorted(), queued.sorted()).allSatisfy {
            abs($0.timeIntervalSince($1)) <= 65
        }
    }
}
