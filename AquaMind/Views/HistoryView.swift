import SwiftUI
import Charts

/// Version 0.4: one data source for day/week/month charts, comparison,
/// calendar drill-down and favourite drinks. Does not own or rewrite records.
struct HistoryView: View {
    @EnvironmentObject private var store: HydrationStore
    @State private var selectedSpan: AnalyticsSpan = .week
    @State private var anchorDate = Date()
    @State private var shownMonth = Date()
    @State private var selectedDay = Date()
    @State private var entryToDelete: WaterEntry?

    private var calendar: Calendar { HydrationAnalytics.mondayCalendar(store.settings.calendar) }
    private var report: AnalyticsReport {
        HydrationAnalytics.report(entries: store.entries, span: selectedSpan,
                                  anchor: anchorDate, calendar: calendar,
                                  profiles: store.settings.customDrinks)
    }
    private var monthDays: [Date?] {
        HydrationAnalytics.calendarDays(month: shownMonth, calendar: calendar)
    }
    private var monthTotals: [Date: Int] {
        HydrationAnalytics.calendarTotals(entries: store.entries, month: shownMonth,
                                          calendar: calendar)
    }
    private var dayEntries: [WaterEntry] { store.entries(on: selectedDay) }
    private var canAdvancePeriod: Bool {
        HydrationAnalytics.periodRange(span: selectedSpan, anchor: anchorDate, calendar: calendar).start <
        HydrationAnalytics.periodRange(span: selectedSpan, anchor: Date(), calendar: calendar).start
    }
    private var canAdvanceMonth: Bool {
        (calendar.dateInterval(of: .month, for: shownMonth)?.start ?? shownMonth) <
        (calendar.dateInterval(of: .month, for: Date())?.start ?? Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 19) {
                    periodSelector
                    overview
                    volumeChart
                    comparisonCard
                    favoriteDrinks
                    calendarCard
                    selectedDayCard
                    if let issue = store.storageIssue {
                        Label(issue, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange).font(.footnote).padding(12)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 40)
            }
            .background(AquaTheme.background.ignoresSafeArea())
            .navigationTitle("Аналитика")
            .confirmationDialog("Удалить запись?", isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ), titleVisibility: .visible) {
                if let entry = entryToDelete {
                    Button("Удалить \(entry.displayName.lowercased()), \(entry.milliliters) мл",
                           role: .destructive) {
                        store.remove(id: entry.id)
                        entryToDelete = nil
                    }
                }
                Button("Отмена", role: .cancel) { entryToDelete = nil }
            } message: {
                Text("Объём за день, графики и статистика будут пересчитаны.")
            }
        }
    }

    private var periodSelector: some View {
        VStack(spacing: 12) {
            Picker("Период", selection: $selectedSpan) {
                ForEach(AnalyticsSpan.allCases) { span in
                    Text(span.title).tag(span)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                Button { movePeriod(-1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Предыдущий период")
                Spacer(minLength: 0)
                Text(report.title.capitalized)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button { movePeriod(1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .disabled(!canAdvancePeriod)
                .accessibilityLabel("Следующий период")
            }
            .foregroundStyle(AquaTheme.cyan)
        }
    }

    private func movePeriod(_ delta: Int) {
        if let next = calendar.date(byAdding: selectedSpan.component, value: delta, to: anchorDate) {
            anchorDate = next
        }
    }

    private var overview: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
            AnalyticsMetric(title: "Всего выпито",
                            value: "\(report.total.formatted()) мл",
                            icon: "drop.fill", tint: AquaTheme.cyan)
            AnalyticsMetric(title: "В среднем за день",
                            value: "\(report.averagePerDay.formatted()) мл",
                            icon: "chart.bar.fill", tint: AquaTheme.blue)
            AnalyticsMetric(title: "Дней с напитками",
                            value: "\(report.activeDays) из \(report.numberOfDays)",
                            icon: "calendar", tint: .green)
            AnalyticsMetric(title: "Записей",
                            value: "\(report.recordCount)",
                            icon: "list.bullet.circle.fill", tint: .orange)
        }
    }

    private var volumeChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(AquaTheme.cyan)
                Text("Объём по времени")
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                Text(selectedSpan == .day ? "По часам" : "По дням")
                    .font(.caption).foregroundStyle(AquaTheme.muted)
            }
            if report.buckets.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle).foregroundStyle(AquaTheme.cyan.opacity(0.7))
                    Text("За выбранный период записей пока нет")
                        .font(.subheadline)
                        .foregroundStyle(AquaTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 204)
            } else {
                if selectedSpan == .week {
                    WeeklyHydrationChart(report: report)
                } else {
                    analyticsBarChart
                }
                HStack(spacing: 6) {
                    ForEach(Array(report.drinks.prefix(3))) { drink in
                        Circle().fill(drink.tint).frame(width: 7, height: 7)
                        Text(drink.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(AquaTheme.muted)
                            .font(.caption2)
                    }
                    if report.drinks.count > 3 {
                        Text("и ещё \(report.drinks.count - 3)")
                            .font(.caption2).foregroundStyle(AquaTheme.muted)
                    }
                }
            }
        }
        .padding(17)
        .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    /// Shared chart geometry, compiled independently of the presentation card.
    private var baseBarChart: some View {
        Chart(report.buckets) { bucket in
            BarMark(x: .value("Период", bucket.index),
                    y: .value("Миллилитры", bucket.milliliters))
                .foregroundStyle(by: .value("Напиток", bucket.identity.id))
                .cornerRadius(3)
        }
        .chartForegroundStyleScale(
            domain: report.drinks.map { $0.identity.id },
            range: report.drinks.map { $0.tint }
        )
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(1, report.bucketLabels.count - 1))
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel()
            }
        }
        .frame(height: 220)
    }

    // Day and month continue to use Swift Charts. The weekly chart uses
    // seven shared SwiftUI columns for bars and labels (no axis padding).
    private var analyticsBarChart: some View {
        baseBarChart.chartXAxis {
            AxisMarks(values: report.axisMarks) { value in
                AxisValueLabel {
                    if let idx = value.as(Int.self),
                       idx >= 0 && idx < report.bucketLabels.count {
                        Text(report.bucketLabels[idx])
                            .font(.system(size: 10))
                    }
                }
            }
        }
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Сравнение периодов", systemImage: "arrow.left.arrow.right")
                .font(.headline).foregroundStyle(.white)
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Выбранный период")
                        .font(.caption).foregroundStyle(AquaTheme.muted)
                    Text("\(report.total.formatted()) мл")
                        .font(.title3.bold()).foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(selectedSpan.previousTitle)
                        .font(.caption).foregroundStyle(AquaTheme.muted)
                    Text("\(report.previousTotal.formatted()) мл")
                        .font(.title3.bold()).foregroundStyle(.white)
                }
            }
            HStack(spacing: 8) {
                if let delta = report.percentageChange {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .foregroundStyle(delta >= 0 ? AquaTheme.cyan : .orange)
                    Text(String(format: "%+.0f%%", delta))
                        .font(.title3.bold())
                        .foregroundStyle(delta >= 0 ? AquaTheme.cyan : .orange)
                } else {
                    Text(report.previousTotal == 0 && report.total > 0
                         ? "Первый результат в сравнении" : "Нет данных для сравнения")
                        .font(.subheadline).foregroundStyle(AquaTheme.muted)
                }
                Spacer()
            }
            Text(report.isCurrentPeriod
                 ? "Сравнение за одинаковую прошедшую часть каждого периода."
                 : "Сравниваются полные календарные периоды.")
                .font(.caption).foregroundStyle(AquaTheme.muted)
        }
        .padding(17)
        .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private var favoriteDrinks: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.pink)
                Text("Любимые напитки")
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                Text("По объёму")
                    .font(.caption).foregroundStyle(AquaTheme.muted)
            }
            if report.drinks.isEmpty {
                Text("Добавь напиток — здесь появится твой рейтинг.")
                    .font(.subheadline)
                    .foregroundStyle(AquaTheme.muted)
            } else {
                HStack(spacing: 10) {
                    Chart(report.drinks) { drink in
                        SectorMark(angle: .value("Объём", drink.milliliters),
                                   innerRadius: .ratio(0.69), angularInset: 1.5)
                            .foregroundStyle(by: .value("Напиток", drink.identity.id))
                    }
                    .chartForegroundStyleScale(
                        domain: report.drinks.map { $0.identity.id },
                        range: report.drinks.map { $0.tint }
                    )
                    .chartLegend(.hidden)
                    .frame(width: 125, height: 125)

                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(report.drinks.prefix(4))) { drink in
                            HStack(spacing: 7) {
                                Circle().fill(drink.tint)
                                    .frame(width: 7, height: 7)
                                Text(drink.title)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Spacer(minLength: 3)
                                Text("\(Int((100.0 * Double(drink.milliliters) / Double(max(1, report.total))).rounded()))%")
                                    .foregroundStyle(AquaTheme.muted)
                            }
                            .font(.caption)
                        }
                    }
                }
                Divider().overlay(Color.white.opacity(0.05))
                ForEach(Array(report.drinks.prefix(3))) { drink in
                    HStack(spacing: 10) {
                        AnalyticsDrinkIcon(drink: drink, size: 34)
                        Text(drink.title)
                            .foregroundStyle(.white)
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 2)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(drink.milliliters.formatted()) мл")
                                .foregroundStyle(drink.tint)
                                .font(.subheadline.weight(.semibold))
                            Text("\(drink.records) записей")
                                .foregroundStyle(AquaTheme.muted)
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .padding(17)
        .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private var calendarCard: some View {
        let days = monthDays
        let totals = monthTotals
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Календарь напитков", systemImage: "calendar")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                HStack(spacing: 13) {
                    Button { moveMonth(-1) } label: {
                        Image(systemName: "chevron.left").frame(width: 34, height: 32)
                    }
                    .accessibilityLabel("Предыдущий месяц")
                    Spacer(minLength: 4)
                    Text(HydrationAnalytics.title(
                        for: HydrationAnalytics.periodRange(span: .month,
                                                            anchor: shownMonth, calendar: calendar),
                        span: .month, timeZone: store.settings.timeZone).capitalized)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Button { moveMonth(1) } label: {
                        Image(systemName: "chevron.right").frame(width: 34, height: 32)
                    }
                    .disabled(!canAdvanceMonth)
                    .accessibilityLabel("Следующий месяц")
                }
                .foregroundStyle(AquaTheme.cyan)
            }

            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(["Пн","Вт","Ср","Чт","Пт","Сб","Вс"], id: \.self) { day in
                    Text(day).font(.caption2.weight(.medium))
                        .foregroundStyle(AquaTheme.muted).frame(maxWidth: .infinity)
                }
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] {
                        let ml = totals[calendar.startOfDay(for: day)] ?? 0
                        let selected = calendar.isDate(day, inSameDayAs: selectedDay)
                        let today = calendar.isDate(day, inSameDayAs: Date())
                        Button {
                            selectedDay = day
                            anchorDate = day
                            selectedSpan = .day
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(calendar.component(.day, from: day))")
                                    .font(.system(size: 13, weight: selected ? .bold : .medium))
                                    .foregroundStyle(selected ? AquaTheme.background : .white)
                                if ml > 0 {
                                    Capsule()
                                        .fill(selected ? AquaTheme.background : AquaTheme.cyan)
                                        .frame(width: 16, height: 3)
                                } else {
                                    Circle()
                                        .fill(Color.clear)
                                        .frame(width: 3, height: 3)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 11)
                                    .fill(selected ? AquaTheme.cyan : Color.white.opacity(today ? 0.09 : 0.02))
                            )
                            .overlay(RoundedRectangle(cornerRadius: 11)
                                .strokeBorder(today && !selected ? AquaTheme.cyan.opacity(0.55)
                                              : Color.clear, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(AquaDate.fullDate(day, timeZone: store.settings.timeZone)), \(ml) миллилитров")
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
            Text("Светлая полоска — в этот день есть записи. Нажми на дату для подробностей.")
                .font(.caption2).foregroundStyle(AquaTheme.muted)
        }
        .padding(17)
        .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 22))
    }

    private func moveMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: shownMonth) {
            shownMonth = next
        }
    }

    private var selectedDayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Записи за день")
                        .font(.headline).foregroundStyle(.white)
                    Text(AquaDate.fullDate(selectedDay, timeZone: store.settings.timeZone))
                        .font(.caption).foregroundStyle(AquaTheme.muted)
                }
                Spacer()
                Button("Сегодня") {
                    selectedDay = Date()
                    shownMonth = Date()
                    anchorDate = Date()
                    selectedSpan = .day
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(AquaTheme.cyan)
            }
            if dayEntries.isEmpty {
                Text("В этот день напитков не записано.")
                    .font(.subheadline)
                    .foregroundStyle(AquaTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(dayEntries) { entry in
                    HStack(spacing: 11) {
                        EntryDrinkIcon(entry: entry, size: 36, profiles: store.settings.customDrinks)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(AnalyticsDrinkIdentity(entry: entry,
                                      profiles: store.settings.customDrinks).title)
                                .foregroundStyle(.white)
                                .font(.subheadline.weight(.medium))
                            Text(entry.volumeLabel)
                                .font(.caption)
                                .foregroundStyle(AnalyticsDrinkIdentity(
                                    entry: entry, profiles: store.settings.customDrinks).tint)
                        }
                        Spacer(minLength: 6)
                        Text(AquaDate.time(entry.date, timeZone: store.settings.timeZone))
                            .font(.subheadline).foregroundStyle(AquaTheme.muted)
                        Button {
                            entryToDelete = entry
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(AquaTheme.muted)
                                .frame(width: 34, height: 38)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Удалить \(entry.milliliters) миллилитров")
                    }
                    if entry.id != dayEntries.last?.id {
                        Divider().overlay(Color.white.opacity(0.04))
                    }
                }
            }
        }
        .padding(17)
        .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 22))
    }
}

private struct AnalyticsMetric: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(AquaTheme.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 91, alignment: .topLeading)
        .padding(14)
        .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 19))
    }
}
