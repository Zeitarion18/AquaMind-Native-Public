import Foundation

@main
struct PlannerSmokeTests {
    static func main() {
        var settings = HydrationSettings()
        settings.remindersEnabled = true
        settings.preferredTimeZoneID = "Europe/Samara"
        settings.wakeHour = 8
        settings.sleepHour = 23
        let cal = settings.calendar

        let dateComponents = DateComponents(timeZone: settings.timeZone, year: 2026, month: 11,
                                            day: 2, hour: 14, minute: 0)
        let now = cal.date(from: dateComponents)!
        let water250 = WaterEntry(date: now, milliliters: 250)
        assert(ReminderPlanner.dailyTotal(entries: [water250], on: now, calendar: cal) == 250)
        let tea = WaterEntry(date: now, milliliters: 500, kind: .tea)
        let coffee = WaterEntry(date: now, milliliters: 150, kind: .coffee)
        let juice = WaterEntry(date: now, milliliters: 250, kind: .juice)
        let broth = WaterEntry(date: now, milliliters: 100, kind: .broth)
        assert(ReminderPlanner.dailyTotal(entries: [water250, tea, coffee, juice, broth],
                                          on: now, calendar: cal) == 1250)
        let oldJSON = """
            {"id":"12345678-1234-1234-1234-1234567890AB","date":0,"milliliters":250}
            """
        let oldEntry = try! JSONDecoder().decode(WaterEntry.self, from: Data(oldJSON.utf8))
        assert(oldEntry.kind == .water && oldEntry.milliliters == 250)
        let roundTrip = try! JSONDecoder().decode(
            WaterEntry.self, from: JSONEncoder().encode(tea))
        assert(roundTrip == tea)
        assert(DrinkKind.allCases.count == 9)

        // Progress: water 1000, tea 500, juice 250, broth 100 out of 2000.
        let mixed = [
            WaterEntry(date: now, milliliters: 1000, kind: .water),
            WaterEntry(date: now, milliliters: 500, kind: .tea),
            WaterEntry(date: now, milliliters: 250, kind: .juice),
            WaterEntry(date: now, milliliters: 100, kind: .broth)
        ]
        let arcs = HydrationRing.segments(entries: mixed, goal: 2000)
        assert(arcs.count == 4)
        assert(arcs.map(\.kind) == [.water, .tea, .juice, .broth])
        let expectedEnds = [0.5, 0.75, 0.875, 0.925]
        for (arc, expected) in zip(arcs, expectedEnds) {
            assert(abs(arc.end - expected) < 0.000001)
        }
        assert(arcs.first!.start == 0 && arcs.last!.end < 1)
        assert(HydrationRing.segments(entries: [], goal: 2000).isEmpty)
        let aboveGoal = HydrationRing.segments(
            entries: [
                WaterEntry(date: now, milliliters: 1500, kind: .water),
                WaterEntry(date: now, milliliters: 1000, kind: .tea)
            ], goal: 2000
        )
        assert(abs(aboveGoal[0].end - 0.6) < 0.000001)
        assert(abs(aboveGoal[1].end - 1.0) < 0.000001)
        let oldArcs = HydrationRing.segments(entries: [oldEntry], goal: 2000)
        assert(oldArcs.count == 1 && oldArcs[0].kind == .water)
        // Volume-aware pauses: a sip must not trigger the old 75-minute delay.
        assert(ReminderPlanner.intervalMinutes(after: 50, minimum: 30) == 30)
        assert(ReminderPlanner.intervalMinutes(after: 100, minimum: 30) == 40)
        assert(ReminderPlanner.intervalMinutes(after: 150, minimum: 30) == 55)
        assert(ReminderPlanner.intervalMinutes(after: 250, minimum: 30) == 75)
        assert(ReminderPlanner.intervalMinutes(after: 350, minimum: 30) == 95)
        assert(ReminderPlanner.intervalMinutes(after: 500, minimum: 30) == 120)
        assert(ReminderPlanner.intervalMinutes(after: 600, minimum: 30) == 140)
        assert(ReminderPlanner.intervalMinutes(after: 350, minimum: 150) == 150)
        assert(ReminderPlanner.repeatMinutes(entries: [], settings: settings, now: now) == 75)

        let dates = ReminderPlanner.upcomingDates(entries: [water250], settings: settings, now: now)
        assert(!dates.isEmpty && dates.count <= ReminderPlanner.notificationLimit)
        assert(dates[0].timeIntervalSince(now) >= 75 * 60)
        assert(dates.allSatisfy { cal.component(.hour, from: $0) < settings.sleepHour })
        assert(zip(dates, dates.dropFirst()).allSatisfy { $0 < $1 })

        // Several drinks in a short period must extend the pause relative
        // to drinking only a single glass.
        let later = now.addingTimeInterval(15 * 60)
        let second = WaterEntry(date: later, milliliters: 300, kind: .tea)
        let cluster = [water250, second]
        let clustered = ReminderPlanner.upcomingDates(entries: cluster, settings: settings, now: later)
        let standalone = ReminderPlanner.upcomingDates(entries: [second], settings: settings, now: later)
        assert(clustered.first! > standalone.first!, "500+ ml over 15 minutes must defer next alert")
        assert(ReminderPlanner.recentVolume(entries: cluster, through: later, calendar: cal) == 550)
        let info = ReminderPlanner.insight(entries: cluster, settings: settings, now: later)
        assert(info.todayMilliliters == 550 && info.recentMilliliters == 550)
        assert(info.headline == "Учтено несколько напитков")
        assert(info.next == clustered.first)
        assert((info.recommendedPauseMinutes ?? 0) >= 120)
        assert(info.explanation.contains("550 мл"))

        // Tiny additional logging must not reset the safety pause to 75m.
        let sip = WaterEntry(date: later.addingTimeInterval(10 * 60),
                             milliliters: 50, kind: .water)
        let newNow = sip.date
        let third = ReminderPlanner.upcomingDates(entries: cluster + [sip], settings: settings, now: newNow)
        assert(third.first!.timeIntervalSince(newNow) >= 140 * 60)

        // Goal reached: no more notifications today; resume tomorrow.
        settings.dailyGoal = 500
        let goalDates = ReminderPlanner.upcomingDates(entries: cluster, settings: settings, now: later)
        assert(!goalDates.contains { cal.isDate($0, inSameDayAs: later) })
        assert(goalDates.first != nil)
        let goalInfo = ReminderPlanner.insight(entries: cluster, settings: settings, now: later)
        assert(goalInfo.headline == "Сегодня цель достигнута")

        // Near bedtime: never schedule inside quiet hours.
        settings.dailyGoal = 2000
        let late = cal.date(byAdding: .hour, value: 8, to: now)!
        let quiet = ReminderPlanner.upcomingDates(entries: cluster, settings: settings, now: late)
        assert(quiet.first != nil)
        assert(quiet.allSatisfy { cal.component(.hour, from: $0) < settings.sleepHour })

        // At least three eligible historical intervals teach a conservative cadence.
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        let history = (0..<4).map { idx in
            WaterEntry(date: yesterday.addingTimeInterval(Double(idx * 130 * 60)),
                       milliliters: 180, kind: .water)
        }
        let learned = ReminderPlanner.learnedIntervalMinutes(entries: history, settings: settings, now: now)
        assert(learned == 130)
        assert(ReminderPlanner.repeatMinutes(entries: history, settings: settings, now: now) == 120)
        let noHistory = ReminderPlanner.learnedIntervalMinutes(entries: [], settings: settings, now: now)
        assert(noHistory == nil)

        // User minimum takes precedence over every smart recommendation.
        settings.minimumReminderMinutes = 180
        assert(ReminderPlanner.intervalMinutes(after: 250, minimum: settings.minimumReminderMinutes) == 180)
        let strict = ReminderPlanner.upcomingDates(entries: [water250], settings: settings, now: now)
        assert(strict.first!.timeIntervalSince(now) >= 180 * 60)

        // The night schedule and time zone do not change stored history.
        // Night is based on local clock, not on whether the first
        // scheduled request happens tomorrow. Bug found in 0.3.0.
        let nightNow = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 4, hour: 1, minute: 3))!
        let midday = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 4, hour: 12, minute: 0))!
        let afterBedtime = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 4, hour: 23, minute: 30))!
        settings.minimumReminderMinutes = 75
        assert(ReminderPlanner.isQuietTime(settings: settings, now: nightNow))
        assert(ReminderPlanner.isQuietTime(settings: settings, now: afterBedtime))
        assert(!ReminderPlanner.isQuietTime(settings: settings, now: midday))
        let nightInsight = ReminderPlanner.insight(entries: [], settings: settings, now: nightNow)
        assert(nightInsight.headline == "Ночной режим")
        assert(nightInsight.explanation.contains("время отдыха"))
        assert(nightInsight.next != nil)
        assert(ReminderPlanner.upcomingDates(entries: [], settings: settings, now: nightNow)
            .allSatisfy { !ReminderPlanner.isQuietTime(settings: settings, now: $0) })

        settings.remindersEnabled = false
        assert(ReminderPlanner.upcomingDates(entries: cluster, settings: settings, now: later).isEmpty)
        assert(ReminderPlanner.insight(entries: cluster, settings: settings, now: later).next == nil)
        // Advanced Analytics regression checks — no archive migrations.
        let analysisNow = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 4, hour: 15, minute: 30))!
        let sameDayMorning = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 4, hour: 9, minute: 10))!
        let sameDayNoon = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 4, hour: 13, minute: 0))!
        let previousDay = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 3, hour: 9, minute: 0))!
        let lastMonth = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 10,
            day: 4, hour: 9, minute: 0))!
        let analyticsEntries = [
            WaterEntry(date: sameDayMorning, milliliters: 250, kind: .water),
            WaterEntry(date: sameDayNoon, milliliters: 500, kind: .tea),
            WaterEntry(date: previousDay, milliliters: 500, kind: .juice),
            WaterEntry(date: lastMonth, milliliters: 1000, kind: .coffee)
        ]
        let dayReport = HydrationAnalytics.report(
            entries: analyticsEntries, span: .day,
            anchor: sameDayNoon, now: analysisNow, calendar: cal)
        assert(dayReport.total == 750 && dayReport.previousTotal == 500)
        assert(dayReport.averagePerDay == 750 && dayReport.recordCount == 2)
        assert(dayReport.activeDays == 1)
        assert(dayReport.bucketLabels.count == 24 && dayReport.buckets.count == 2)
        assert(dayReport.topDrink?.kind == .tea)
        assert(abs((dayReport.percentageChange ?? 0) - 50) < 0.001)
        let weekReport = HydrationAnalytics.report(
            entries: analyticsEntries, span: .week,
            anchor: analysisNow, now: analysisNow, calendar: cal)
        assert(weekReport.total == 1250 && weekReport.activeDays == 2)
        assert(weekReport.bucketLabels == ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
        assert(cal.component(.weekday, from: weekReport.range.start) == 2)
        assert(weekReport.averagePerDay == 416)
        let monthReport = HydrationAnalytics.report(
            entries: analyticsEntries, span: .month,
            anchor: analysisNow, now: analysisNow, calendar: cal)
        assert(monthReport.total == 1250 && monthReport.bucketLabels.count == 30)
        assert(monthReport.previousTotal == 1000)
        assert(monthReport.numberOfDays == 4)
        let october = HydrationAnalytics.report(
            entries: analyticsEntries, span: .month,
            anchor: lastMonth, now: analysisNow, calendar: cal)
        assert(october.bucketLabels.count == 31 && october.total == 1000)
        assert(!october.isCurrentPeriod && october.numberOfDays == 31)

        let calendarGrid = HydrationAnalytics.calendarDays(month: analysisNow, calendar: cal)
        assert(calendarGrid.count % 7 == 0 && calendarGrid.count >= 28)
        let actualNovemberDays = calendarGrid.compactMap { $0 }
        assert(actualNovemberDays.count == 30)
        assert(cal.component(.day, from: actualNovemberDays.first!) == 1)
        assert(cal.component(.day, from: actualNovemberDays.last!) == 30)
        let calendarData = HydrationAnalytics.calendarTotals(
            entries: analyticsEntries, month: analysisNow, calendar: cal)
        assert(calendarData[cal.startOfDay(for: sameDayMorning)] == 750)
        assert(calendarData[cal.startOfDay(for: previousDay)] == 500)
        assert(calendarData[cal.startOfDay(for: lastMonth)] == nil)
        assert(HydrationAnalytics.report(entries: [], span: .week,
            anchor: analysisNow, now: analysisNow, calendar: cal).drinks.isEmpty)
        assert(HydrationAnalytics.report(entries: [oldEntry], span: .day,
            anchor: oldEntry.date, now: analysisNow, calendar: cal).total == 250)

        // Regression: Sunday must remain the seventh week bucket even when
        // the other six days are empty.
        let sunday = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 1, hour: 14, minute: 15))!
        let sundayReport = HydrationAnalytics.report(
            entries: [WaterEntry(date: sunday, milliliters: 350, kind: .water)],
            span: .week, anchor: sunday, now: analysisNow, calendar: cal)
        assert(sundayReport.total == 350)
        assert(sundayReport.bucketLabels.count == 7)
        assert(sundayReport.bucketLabels[6] == "Вс")
        assert(sundayReport.axisMarks == [0, 1, 2, 3, 4, 5, 6])
        assert(sundayReport.buckets.count == 1 && sundayReport.buckets[0].index == 6)

        // One shared seven-column geometry aligns bars and labels at any width.
        let slots = WeeklyChartLayout.slots(report: weekReport)
        assert(slots.count == 7 && slots.map(\.label) ==
            ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"])
        assert(slots.reduce(0) { $0 + $1.total } == weekReport.total)
        for plotWidth in [210.0, 245.0, 287.0, 350.0, 410.0] {
            let width = WeeklyChartLayout.columnWidth(plotWidth: plotWidth)
            assert(abs(Double(width) * 7 - plotWidth) < 0.00001)
            for index in 0..<7 {
                let midpoint = Double(WeeklyChartLayout.centerX(
                    index: index, plotWidth: plotWidth))
                assert(abs(midpoint - (Double(index) + 0.5) * Double(width)) < 0.00001)
            }
        }
        let onlySunday = WeeklyChartLayout.slots(report: sundayReport)
        assert(onlySunday.count == 7)
        assert(onlySunday[6].label == "Вс" && onlySunday[6].total == 350)
        assert(onlySunday[0].total == 0 && onlySunday[5].total == 0)
        assert(WeeklyChartLayout.axisMaximum(slots: onlySunday) >= 350)
        let emptyWeek = HydrationAnalytics.report(
            entries: [], span: .week, anchor: analysisNow,
            now: analysisNow, calendar: cal)
        assert(WeeklyChartLayout.slots(report: emptyWeek).allSatisfy { $0.total == 0 })

        // Critical regression: merely advancing the clock or reopening the app
        // must NEVER postpone a still-pending alert by another 20 minutes.
        settings.remindersEnabled = true
        settings.dailyGoal = 2000
        settings.minimumReminderMinutes = 75
        settings.wakeHour = 7
        settings.sleepHour = 23

        let clock1251 = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 4, hour: 12, minute: 51))!
        let clock1252 = clock1251.addingTimeInterval(60)
        let drank1156 = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 4, hour: 11, minute: 56))!
        let precise13011 = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 4, hour: 13, minute: 11))!
        let recentDrink = WaterEntry(date: drank1156, milliliters: 250, kind: .water)
        let firstAt1251 = ReminderPlanner.upcomingDates(
            entries: [recentDrink], settings: settings, now: clock1251)
        let firstAt1252 = ReminderPlanner.upcomingDates(
            entries: [recentDrink], settings: settings, now: clock1252)
        assert(firstAt1251.first == precise13011)
        assert(firstAt1252.first == precise13011)
        assert(firstAt1251 == firstAt1252)
        assert(ReminderPlanner.notificationID(for: firstAt1251[0]) ==
               ReminderPlanner.notificationID(for: firstAt1252[0]))
        let aMinuteBefore = ReminderPlanner.upcomingDates(
            entries: [recentDrink], settings: settings,
            now: precise13011.addingTimeInterval(-60))
        assert(aMinuteBefore.first == precise13011)
        let afterFirst = ReminderPlanner.upcomingDates(
            entries: [recentDrink], settings: settings,
            now: precise13011.addingTimeInterval(60))
        assert(afterFirst.first! > precise13011)
        assert(afterFirst.first!.timeIntervalSince(precise13011) >= 75 * 60)

        // Even with no entries, a fixed daily clock anchor must not slide.
        let noDrink1251 = ReminderPlanner.upcomingDates(
            entries: [], settings: settings, now: clock1251)
        let noDrink1252 = ReminderPlanner.upcomingDates(
            entries: [], settings: settings, now: clock1252)
        assert(!noDrink1251.isEmpty && noDrink1251.first == noDrink1252.first)
        assert(noDrink1251 == noDrink1252)
        assert(Set(noDrink1251.map(ReminderPlanner.notificationID(for:))).count ==
               noDrink1251.count)

        // Legacy app persisted minimum=75. Versioned migration recognizes
        // the old default without overwriting an explicit custom minimum.
        let oldDefault = """
        {"dailyGoal":2000,"wakeHour":7,"sleepHour":23,
         "remindersEnabled":true,"minimumReminderMinutes":75,
         "preferredTimeZoneID":"Europe/Samara"}
        """
        let migrated = try! JSONDecoder().decode(HydrationSettings.self,
                                                  from: Data(oldDefault.utf8))
        assert(migrated.minimumReminderMinutes == 30)
        assert(migrated.adaptiveReminderVersion == 1)
        let migratedAgain = try! JSONDecoder().decode(
            HydrationSettings.self, from: JSONEncoder().encode(migrated))
        assert(migratedAgain == migrated)
        let oldCustom = oldDefault.replacingOccurrences(of:
            "\"minimumReminderMinutes\":75", with: "\"minimumReminderMinutes\":90")
        let preservedCustom = try! JSONDecoder().decode(
            HydrationSettings.self, from: Data(oldCustom.utf8))
        assert(preservedCustom.minimumReminderMinutes == 90)
        var explicitSeventyFive = migrated
        explicitSeventyFive.minimumReminderMinutes = 75
        let roundTrip75 = try! JSONDecoder().decode(
            HydrationSettings.self, from: JSONEncoder().encode(explicitSeventyFive))
        assert(roundTrip75.minimumReminderMinutes == 75)

        let sipAt1300 = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 4, hour: 13, minute: 0))!
        settings.minimumReminderMinutes = 30
        let smallSip = WaterEntry(date: sipAt1300, milliliters: 50)
        let sipDates = ReminderPlanner.upcomingDates(
            entries: [smallSip], settings: settings, now: sipAt1300)
        assert(sipDates.first!.timeIntervalSince(sipAt1300) == 30 * 60)
        let oneMinuteLater = ReminderPlanner.upcomingDates(
            entries: [smallSip], settings: settings,
            now: sipAt1300.addingTimeInterval(60))
        assert(sipDates.first == oneMinuteLater.first)
        let bigDrink = WaterEntry(date: sipAt1300, milliliters: 500, kind: .tea)
        let bigDates = ReminderPlanner.upcomingDates(
            entries: [bigDrink], settings: settings, now: sipAt1300)
        assert(bigDates.first! > sipDates.first!)
        let clusteredDates = ReminderPlanner.upcomingDates(
            entries: [smallSip, bigDrink], settings: settings, now: sipAt1300)
        assert(clusteredDates.first! >= bigDates.first!)

        // Sleep schedules: Monday-Friday 06:30, weekends 11:30.
        var weekly = HydrationSettings()
        weekly.remindersEnabled = true
        weekly.preferredTimeZoneID = "Europe/Samara"
        let weekCal = weekly.calendar
        for day in 2...6 {
            assert(weekly.schedule(for: day).wakeMinute == 390)
            assert(weekly.schedule(for: day).sleepMinute == 1380)
        }
        assert(weekly.schedule(for: 1).wakeMinute == 690)
        assert(weekly.schedule(for: 7).wakeMinute == 690)
        let monday = weekCal.date(from: DateComponents(
            timeZone: weekly.timeZone, year: 2026, month: 11,
            day: 2, hour: 6, minute: 45))!
        let saturday = weekCal.date(from: DateComponents(
            timeZone: weekly.timeZone, year: 2026, month: 11,
            day: 7, hour: 7, minute: 0))!
        let saturdayStart = weekCal.date(from: DateComponents(
            timeZone: weekly.timeZone, year: 2026, month: 11,
            day: 7, hour: 11, minute: 30))!
        assert(!ReminderPlanner.isQuietTime(settings: weekly, now: monday))
        assert(ReminderPlanner.isQuietTime(settings: weekly, now: saturday))
        assert(!ReminderPlanner.isQuietTime(settings: weekly, now: saturdayStart))
        let saturdayAlerts = ReminderPlanner.upcomingDates(
            entries: [], settings: weekly, now: saturday)
        assert(weekCal.component(.hour, from: saturdayAlerts.first!) == 12)
        assert(weekCal.component(.minute, from: saturdayAlerts.first!) == 30)

        // Early wake on a weekend brings the first reminder forward,
        // without changing the next week's standing schedule.
        let earlySaturday = weekCal.date(from: DateComponents(
            timeZone: weekly.timeZone, year: 2026, month: 11,
            day: 7, hour: 8, minute: 10))!
        weekly.wokeUpAt = earlySaturday
        let earlierAlerts = ReminderPlanner.upcomingDates(
            entries: [], settings: weekly, now: earlySaturday)
        assert(earlierAlerts.first!.timeIntervalSince(earlySaturday) == 30 * 60)
        assert(weekly.schedule(for: 7).wakeMinute == 690)
        weekly.wokeUpAt = nil

        // Manual sleep pauses new reminders and expires at the next
        // configured wake time; recorded drinks are never deleted.
        let bedtimeFriday = weekCal.date(from: DateComponents(
            timeZone: weekly.timeZone, year: 2026, month: 11,
            day: 6, hour: 20, minute: 20))!
        weekly.sleepStartedAt = bedtimeFriday
        weekly.sleepPauseUntil = ReminderPlanner.nextScheduledWake(
            after: bedtimeFriday, settings: weekly)
        assert(ReminderPlanner.isQuietTime(settings: weekly, now: bedtimeFriday))
        assert(weekly.sleepPauseUntil == saturdayStart)
        let paused = ReminderPlanner.upcomingDates(
            entries: [], settings: weekly, now: bedtimeFriday)
        assert(!paused.contains {
            $0 >= bedtimeFriday && $0 < saturdayStart
        })
        assert(paused.first! >= saturdayStart)

        // Overnight schedule (Saturday into early Sunday) is supported.
        weekly.sleepStartedAt = nil
        weekly.sleepPauseUntil = nil
        weekly.weeklySchedule.removeAll { $0.weekday == 7 }
        weekly.weeklySchedule.append(DaySchedule(
            weekday: 7, wakeMinute: 12 * 60, sleepMinute: 1 * 60))
        let saturdayNight = weekCal.date(from: DateComponents(
            timeZone: weekly.timeZone, year: 2026, month: 11,
            day: 8, hour: 0, minute: 30))!
        assert(!ReminderPlanner.isQuietTime(settings: weekly, now: saturdayNight))
        let sundayMorning = weekCal.date(from: DateComponents(
            timeZone: weekly.timeZone, year: 2026, month: 11,
            day: 8, hour: 2, minute: 30))!
        assert(ReminderPlanner.isQuietTime(settings: weekly, now: sundayMorning))

        let archivePrevious = """
            {"dailyGoal":2000,"wakeHour":7,"sleepHour":23,
             "remindersEnabled":true,"minimumReminderMinutes":30,
             "preferredTimeZoneID":"Europe/Samara","adaptiveReminderVersion":1}
            """
        let decodedOldSchedule = try! JSONDecoder().decode(
            HydrationSettings.self, from: Data(archivePrevious.utf8))
        assert(decodedOldSchedule.weeklySchedule.count == 7)
        assert(decodedOldSchedule.wakeHour == 7)  // legacy property retained
        let persisted = try! JSONDecoder().decode(
            HydrationSettings.self, from: JSONEncoder().encode(weekly))
        assert(persisted == weekly)

        // Widget mirror is derived, never modifies the canonical archive.
        let widgetSnapshot = AquaMindWidgetSnapshot.make(
            entries: [WaterEntry(date: analysisNow, milliliters: 250, kind: .water),
                      WaterEntry(date: analysisNow, milliliters: 300, kind: .tea),
                      WaterEntry(date: lastMonth, milliliters: 1000, kind: .coffee)],
            settings: weekly, now: analysisNow)
        assert(widgetSnapshot.milliliters == 550)
        assert(widgetSnapshot.dailyGoal == weekly.dailyGoal)
        assert(widgetSnapshot.portions.count == 2)
        assert(widgetSnapshot.progress == 0.275)
        let widgetEncoded = try! JSONEncoder().encode(widgetSnapshot)
        let widgetDecoded = try! JSONDecoder().decode(
            AquaMindWidgetSnapshot.self, from: widgetEncoded)
        assert(widgetDecoded == widgetSnapshot)
        let tomorrowWidget = widgetSnapshot.current(
            on: analysisNow.addingTimeInterval(86_400))
        assert(tomorrowWidget.milliliters == 0)
        assert(tomorrowWidget.portions.isEmpty)
        assert(tomorrowWidget.dailyGoal == widgetSnapshot.dailyGoal)
        let originalCount = analyticsEntries.count
        _ = AquaMindWidgetSnapshot.make(entries: analyticsEntries,
                                        settings: weekly, now: analysisNow)
        assert(analyticsEntries.count == originalCount)

        // 0.6.0 migration: an old archive has no customization keys.
        let oldSettings = try! JSONDecoder().decode(
            HydrationSettings.self, from: Data(archivePrevious.utf8))
        assert(oldSettings.quickVolumes == [150, 250, 350])
        assert(oldSettings.customDrinks.isEmpty && oldSettings.vessels.isEmpty)
        assert(oldSettings.favorites.isEmpty)
        assert(!oldEntry.isEstimated && oldEntry.customDrinkName == nil)
        assert(oldEntry.displayName == "Вода" && oldEntry.volumeLabel == "250 мл")

        // User-defined profile is stored in settings, with its display data
        // snapshotted into each entry to survive profile deletion.
        let profile = CustomDrink(name: "Какао", symbol: "mug.fill", palette: 4)
        var customized = HydrationSettings()
        customized.customDrinks = [profile]
        customized.vessels = [DrinkVessel(name: "Моя кружка", milliliters: 325)]
        customized.quickVolumes = [75, 200, 450]
        customized.favorites = [
            DrinkFavorite(kind: .other, customDrinkID: profile.id,
                          customName: profile.name, milliliters: 325),
            DrinkFavorite(kind: .water, customDrinkID: nil,
                          customName: nil, milliliters: 250)
        ]
        let customEntry = WaterEntry(date: analysisNow, milliliters: 325,
                                     kind: .other, customDrinkName: profile.name,
                                     customDrinkSymbol: profile.symbol,
                                     customDrinkPalette: profile.palette)
        let estimate = WaterEntry(date: analysisNow, milliliters: 50,
                                  kind: .water, isEstimated: true)
        let entriesBefore = [oldEntry, customEntry, estimate]
        let archive = HydrationArchive(entries: entriesBefore, settings: customized)
        let restored = try! JSONDecoder().decode(
            HydrationArchive.self, from: JSONEncoder().encode(archive))
        assert(restored.entries == entriesBefore)
        assert(restored.settings == customized)
        assert(restored.settings.quickVolumes == [75, 200, 450])
        assert(restored.settings.vessels[0].milliliters == 325)
        assert(restored.entries[1].displayName == "Какао")
        assert(restored.entries[1].customDrinkPalette == 4)
        assert(restored.entries[2].isEstimated && restored.entries[2].volumeLabel == "≈ 50 мл")
        assert(restored.entries[0].isEstimated == false)
        assert(ReminderPlanner.dailyTotal(entries: [customEntry, estimate],
                                          on: analysisNow, calendar: cal) == 375)

        // Removing a custom profile must not erase or rename historical records.
        customized.customDrinks.removeAll()
        let afterDeletion = HydrationArchive(entries: entriesBefore,
                                             settings: customized)
        let reloaded = try! JSONDecoder().decode(
            HydrationArchive.self, from: JSONEncoder().encode(afterDeletion))
        assert(reloaded.entries.count == 3)
        assert(reloaded.entries[1].displayName == "Какао")
        assert(reloaded.entries[2].isEstimated)
        assert(reloaded.settings.customDrinks.isEmpty)

        // New settings must not alter the steady notification schedule.
        let withProfiles = ReminderPlanner.upcomingDates(
            entries: [recentDrink], settings: customized, now: clock1251)
        let withoutProfiles = ReminderPlanner.upcomingDates(
            entries: [recentDrink], settings: HydrationSettings(), now: clock1251)
        assert(withProfiles == withoutProfiles)
        // 0.7.0: analytics must distinguish different user-defined drinks
        // (and built-in "Other") even though all use DrinkKind.other in storage.
        let cocoa = WaterEntry(date: analysisNow, milliliters: 300, kind: .other,
                               customDrinkName: "Какао",
                               customDrinkSymbol: "mug.fill", customDrinkPalette: 4)
        let mors = WaterEntry(date: analysisNow, milliliters: 200, kind: .other,
                              customDrinkName: "Морс",
                              customDrinkSymbol: "wineglass.fill", customDrinkPalette: 2)
        let otherPlain = WaterEntry(date: analysisNow, milliliters: 50, kind: .other)
        let cocoaAgain = WaterEntry(date: analysisNow, milliliters: 150, kind: .other,
                                    customDrinkName: "Какао",
                                    customDrinkSymbol: "mug.fill", customDrinkPalette: 4)
        let customReport = HydrationAnalytics.report(
            entries: [cocoa, mors, otherPlain, cocoaAgain],
            span: .day, anchor: analysisNow, now: analysisNow, calendar: cal)
        assert(customReport.total == 700)
        assert(customReport.recordCount == 4)
        assert(customReport.drinks.count == 3)
        assert(customReport.buckets.count == 3)
        assert(customReport.drinks.reduce(0) { $0 + $1.milliliters } == customReport.total)
        assert(customReport.buckets.reduce(0) { $0 + $1.milliliters } == customReport.total)
        let cocoaRank = customReport.drinks.first(where: { $0.title == "Какао" })!
        assert(cocoaRank.milliliters == 450 && cocoaRank.records == 2)
        assert(cocoaRank.identity.customPalette == 4)
        assert(customReport.drinks.contains {
            $0.title == "Морс" && $0.milliliters == 200
        })
        assert(customReport.drinks.contains {
            $0.title == "Другое" && $0.milliliters == 50
        })
        let newWeekReport = HydrationAnalytics.report(
            entries: [cocoa, mors, otherPlain, cocoaAgain],
            span: .week, anchor: analysisNow, now: analysisNow, calendar: cal)
        assert(newWeekReport.total == 700)
        assert(newWeekReport.buckets.count == 3)
        assert(WeeklyChartLayout.slots(report: newWeekReport)
               .reduce(0) { $0 + $1.total } == 700)

        // Learn separate day types only from sufficient *distinct* days.
        var weekdayAndWeekend: [WaterEntry] = []
        func makeSessions(day: Int, gap: Int) -> [WaterEntry] {
            let start = cal.date(from: DateComponents(
                timeZone: settings.timeZone, year: 2026, month: 11,
                day: day, hour: 9, minute: 0))!
            return (0..<3).map { index in
                WaterEntry(date: start.addingTimeInterval(Double(index * gap * 60)),
                           milliliters: 150, kind: .water)
            }
        }
        weekdayAndWeekend += makeSessions(day: 2, gap: 95)   // Mon
        weekdayAndWeekend += makeSessions(day: 5, gap: 95)   // Thu
        weekdayAndWeekend += makeSessions(day: 1, gap: 145)  // Sun
        weekdayAndWeekend += makeSessions(day: 7, gap: 145)  // Sat

        var learningSettings = HydrationSettings()
        learningSettings.preferredTimeZoneID = settings.preferredTimeZoneID
        learningSettings.remindersEnabled = true
        let nextSunday = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 8, hour: 13, minute: 0))!
        let nextMonday = cal.date(from: DateComponents(
            timeZone: settings.timeZone, year: 2026, month: 11,
            day: 9, hour: 13, minute: 0))!
        assert(ReminderPlanner.learnedIntervalForDayType(
            entries: weekdayAndWeekend, settings: learningSettings, day: nextSunday) == 145)
        assert(ReminderPlanner.learnedIntervalForDayType(
            entries: weekdayAndWeekend, settings: learningSettings, day: nextMonday) == 95)
        assert(ReminderPlanner.repeatMinutes(
            entries: weekdayAndWeekend, settings: learningSettings, now: nextSunday) == 120)
        assert(ReminderPlanner.repeatMinutes(
            entries: weekdayAndWeekend, settings: learningSettings, now: nextMonday) == 95)
        assert(ReminderPlanner.habitSummary(
            entries: weekdayAndWeekend, settings: learningSettings,
            day: nextSunday).contains("выходных"))
        assert(ReminderPlanner.habitSummary(
            entries: weekdayAndWeekend, settings: learningSettings,
            day: nextMonday).contains("будней"))
        // Only one observed weekend day should not become a "habit".
        assert(ReminderPlanner.learnedIntervalForDayType(
            entries: makeSessions(day: 7, gap: 145),
            settings: learningSettings, day: nextSunday) == nil)
        let stableBefore = ReminderPlanner.upcomingDates(
            entries: weekdayAndWeekend, settings: learningSettings, now: nextMonday)
        let stableAfter = ReminderPlanner.upcomingDates(
            entries: weekdayAndWeekend, settings: learningSettings,
            now: nextMonday.addingTimeInterval(60))
        assert(stableBefore == stableAfter)

        // Status is based on exact dates in the iOS queue, not merely count.
        let aDate = nextMonday.addingTimeInterval(1800)
        let bDate = nextMonday.addingTimeInterval(4200)
        assert(NotificationQueueComparison.matches(
            planned: [aDate, bDate], queued: [bDate, aDate]))
        assert(NotificationQueueComparison.matches(
            planned: [aDate], queued: [aDate.addingTimeInterval(59)]))
        assert(!NotificationQueueComparison.matches(
            planned: [aDate], queued: [aDate.addingTimeInterval(130)]))
        assert(!NotificationQueueComparison.matches(
            planned: [aDate], queued: []))

        // Backward compatible old customization/notification/sleep behavior.
        assert(restored.entries == entriesBefore)
        assert(decodedOldSchedule.weeklySchedule.count == 7)
        print("AquaMind 0.7.0 passed: workday/weekend learning, custom drinks separated, iOS queue diagnostics, history and sleep")
    }
}
