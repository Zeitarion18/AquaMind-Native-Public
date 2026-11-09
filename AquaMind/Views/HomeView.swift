import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var store: HydrationStore
    @State private var showCustomAmount = false
    @State private var showEstimate = false
    @State private var showReminderExplanation = false
    @State private var entryToDelete: WaterEntry?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 19)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AquaTheme.background)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        progressPanel
                        drinkPicker
                        quickLogPanel
                        personalQuickPanel
                        breakdownPanel
                        sleepStatusCard
                        reminderPanel
                        recentPanel
                        if let issue = store.storageIssue {
                            Label(issue, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(.orange).padding()
                        }
                    }
                    .padding(.horizontal, 19)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .background(AquaTheme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCustomAmount) { AddDrinkSheet() }
            .sheet(isPresented: $showEstimate) { EstimateDrinkSheet() }
            .confirmationDialog("Удалить запись?", isPresented: Binding(
                get: { entryToDelete != nil },
                set: { if !$0 { entryToDelete = nil } }
            ), titleVisibility: .visible) {
                if let entry = entryToDelete {
                    Button("Удалить \(entry.kind.title.lowercased()), \(entry.milliliters) мл", role: .destructive) {
                        store.remove(id: entry.id)
                        entryToDelete = nil
                    }
                }
                Button("Отмена", role: .cancel) { entryToDelete = nil }
            } message: {
                Text("Общий объём жидкости и расписание напоминаний будут пересчитаны.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AQUAMIND")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(3).foregroundStyle(AquaTheme.cyan)
                Text("Твой баланс жидкости")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.85)
                    .lineLimit(1)
                Text(AquaDate.heading(Date.now, timeZone: store.settings.timeZone))
                    .font(.subheadline).foregroundStyle(AquaTheme.muted)
            }
            Spacer(minLength: 8)
            DrinkIcon(kind: .water, size: 44)
        }
    }

    private var progressPanel: some View {
        VStack(spacing: 14) {
            ZStack {
                LiquidProgressRing(slices: store.ringSegments)

                VStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 25))
                        .foregroundStyle(
                            LinearGradient(
                                colors: store.ringSegments.isEmpty
                                    ? [AquaTheme.cyan, AquaTheme.blue]
                                    : store.ringSegments.map { $0.identity.tint },
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    Text("\(store.todayTotal)")
                        .font(.system(size: 45, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                        .foregroundStyle(.white)
                    Text("из \(store.settings.dailyGoal) мл")
                        .font(.subheadline).foregroundStyle(AquaTheme.muted)
                }
            }
            .frame(width: 218, height: 218)
            .padding(.vertical, 4)

            Text(store.todayTotal >= store.settings.dailyGoal ? "Цель по жидкости достигнута! ✨" : "Учитываем все напитки")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
            Text("\(Int(store.progress * 100))% дневной цели")
                .font(.footnote).foregroundStyle(AquaTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 29)
                .fill(LinearGradient(colors: [
                    Color(red: 0.08, green: 0.19, blue: 0.30), AquaTheme.panel
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(RoundedRectangle(cornerRadius: 29).stroke(AquaTheme.cyan.opacity(0.15), lineWidth: 1))
    }

    private var drinkPicker: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Что ты выпил?")
                .font(.headline).foregroundStyle(.white)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 9),
                GridItem(.flexible(), spacing: 9),
                GridItem(.flexible(), spacing: 9)
            ], spacing: 10) {
                ForEach(DrinkKind.allCases) { kind in
                    let isSelected = store.selectedDrink == kind
                    Button {
                        store.selectDrink(kind)
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        VStack(spacing: 8) {
                            DrinkIcon(kind: kind, size: 49)
                            Text(kind.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : AquaTheme.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(isSelected ? kind.tint.opacity(0.20) : AquaTheme.panel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(isSelected ? kind.tint.opacity(0.8) : Color.clear,
                                              lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Выбрать: \(kind.title)")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            if !store.settings.customDrinks.isEmpty {
                HStack(spacing: 8) {
                    Text("Мои напитки")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Image(systemName: "sparkles")
                        .foregroundStyle(AquaTheme.cyan)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3),
                          spacing: 10) {
                    ForEach(store.settings.customDrinks) { custom in
                        let selected = store.activeCustomDrink?.id == custom.id
                        let tint = PersonalDrinkPalette.tint(custom.palette)
                        Button {
                            store.selectCustomDrink(custom.id)
                        } label: {
                            VStack(spacing: 7) {
                                PersonalDrinkIcon(name: custom.name, symbol: custom.symbol,
                                                  palette: custom.palette, size: 49)
                                Text(custom.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(selected ? .white : AquaTheme.muted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(selected ? tint.opacity(0.2) : AquaTheme.panel,
                                        in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18)
                                .strokeBorder(selected ? tint : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var quickLogPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Добавить: \(store.selectedDrinkTitle.lowercased())")
                    .font(.headline).foregroundStyle(.white)
                Spacer()
                Text("мл").font(.caption).foregroundStyle(AquaTheme.muted)
            }
            HStack(spacing: 10) {
                ForEach(store.settings.quickVolumes.indices, id: \.self) { index in
                    let ml = store.settings.quickVolumes[index]
                    Button {
                        store.addSelected(ml)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: "plus.circle.fill").font(.title3)
                            Text("\(ml)").font(.system(.headline, design: .rounded))
                            Text("мл").font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(store.activeCustomDrink.map { PersonalDrinkPalette.tint($0.palette) } ?? store.selectedDrink.tint)
                        .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Добавить \(ml) миллилитров: \(store.selectedDrinkTitle)")
                }
                Button { showCustomAmount = true } label: {
                    VStack(spacing: 7) {
                        Image(systemName: "keyboard").font(.title3)
                        Text("Свой").font(.system(.headline, design: .rounded))
                        Text("объём").font(.caption2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(.white)
                    .background(AquaTheme.blue.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var personalQuickPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Label("Личные быстрые действия", systemImage: "heart.fill")
                    .foregroundStyle(.white)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 2)
                Button {
                    showEstimate = true
                } label: {
                    Label("На глаз", systemImage: "drop.halffull")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(AquaTheme.cyan)
            }
            if !store.settings.favorites.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(store.settings.favorites) { item in
                            Button {
                                store.addFavorite(item)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.customDrinkID.flatMap { id in
                                        store.settings.customDrinks.first(where: { $0.id == id })?.name
                                    } ?? item.customName ?? item.kind.title)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    Text("+\(item.milliliters) мл")
                                        .font(.subheadline.bold())
                                }
                                .foregroundStyle(AquaTheme.cyan)
                                .padding(12)
                                .background(AquaTheme.panel,
                                            in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !store.settings.vessels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(store.settings.vessels) { vessel in
                            Button {
                                store.addSelected(vessel.milliliters)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                Label("\(vessel.name) · \(vessel.milliliters) мл",
                                      systemImage: "cup.and.saucer.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                                    .padding(11)
                                    .background(AquaTheme.panel,
                                                in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if store.settings.favorites.isEmpty && store.settings.vessels.isEmpty {
                Text("Добавь любимые напитки и посуду в настройках. А примерный объём можно записать уже сейчас.")
                    .font(.caption)
                    .foregroundStyle(AquaTheme.muted)
            }
        }
    }

    private var breakdownPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Состав напитков")
                .font(.headline).foregroundStyle(.white)
            if store.todayBreakdown.isEmpty {
                Text("Здесь появится распределение по напиткам.")
                    .font(.subheadline).foregroundStyle(AquaTheme.muted)
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(store.todayBreakdown, id: \.identity.id) { item in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(item.identity.tint.gradient)
                                .frame(width: max(0, (geometry.size.width - CGFloat(max(0, store.todayBreakdown.count - 1)) * 2) *
                                              CGFloat(item.amount) / CGFloat(max(store.todayTotal, 1))))
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                ForEach(store.todayBreakdown, id: \.identity.id) { item in
                    HStack(spacing: 10) {
                        Circle().fill(item.identity.tint).frame(width: 9, height: 9)
                        Text(item.identity.title)
                            .foregroundStyle(.white)
                        Spacer()
                        Text("\(item.amount) мл")
                            .foregroundStyle(AquaTheme.muted)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 20))
    }

    private var sleepStatusCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let sleeping = store.settings.isManualSleepActive(at: timeline.date)
            let awaitingWake = store.settings.wakeConfirmationPending(at: timeline.date)
            let today = store.settings.schedule(for:
                store.settings.calendar.component(.weekday, from: timeline.date))
            HStack(spacing: 12) {
                Image(systemName: sleeping ? "moon.zzz.fill" : awaitingWake ? "sunrise.fill" : "sun.horizon.fill")
                    .foregroundStyle(AquaTheme.cyan)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(sleeping ? "Пауза на сон" : awaitingWake ? "Отметь пробуждение" : "Твой режим дня")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(sleeping
                         ? "До \(AquaDate.time(store.settings.sleepPauseUntil ?? timeline.date, timeZone: store.settings.timeZone)) или «Проснулся»"
                         : awaitingWake
                           ? "Автопауза закончилась. Укажи время подъёма."
                           : "Сегодня: \(today.wakeLabel)–\(today.sleepLabel)")
                        .font(.caption).foregroundStyle(AquaTheme.muted)
                }
                Spacer(minLength: 0)
                Button(awaitingWake ? "Проснулся" : "Лёг спать") {
                    if awaitingWake { store.wakeUp() }
                    else { store.beginSleep() }
                }
                .buttonStyle(.bordered)
                .tint(AquaTheme.cyan)
                .font(.footnote.weight(.medium))
            }
            .padding(15)
            .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 19))
        }
    }

    private var reminderPanel: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let info = ReminderPlanner.insight(entries: store.entries,
                                               settings: store.settings, now: timeline.date)
            let night = ReminderPlanner.isQuietTime(settings: store.settings, now: timeline.date)
            let paused = store.settings.remindersPaused(at: timeline.date)
            let pendingTime: Date? = {
                switch store.reminderQueueStatus {
                case .confirmed(let date, _), .postponed(let date):
                    return date > timeline.date ? date : nil
                default: return nil
                }
            }()
            let shownTime = pendingTime ?? info.next
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: night && store.settings.remindersEnabled
                          ? "moon.stars.fill" : "bell.badge.fill")
                        .font(.title3)
                        .foregroundStyle(AquaTheme.cyan)
                    Text("Smart Hydration 3.0")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    if paused && store.settings.remindersEnabled {
                        Text("ПАУЗА")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(AquaTheme.cyan)
                    } else if night && store.settings.remindersEnabled {
                        Text("НОЧНОЙ РЕЖИМ")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(AquaTheme.cyan)
                    }
                }

                if store.settings.remindersEnabled {
                    Label("\(store.settings.reminderStyle.title) режим · \(store.settings.reminderSoundEnabled ? "со звуком" : "без звука")",
                          systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(AquaTheme.cyan)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(pendingTime == nil ? "Расчётное следующее напоминание" : "Следующее напоминание iPhone")
                            .font(.caption)
                            .foregroundStyle(AquaTheme.muted)
                        if let date = shownTime {
                            Text(AquaDate.time(date, timeZone: store.settings.timeZone))
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Text(AquaDate.fullDate(date, timeZone: store.settings.timeZone))
                                .font(.subheadline).foregroundStyle(AquaTheme.muted)
                            if let verified = pendingTime {
                                Label(ReminderCountdown.message(until: verified, from: timeline.date),
                                      systemImage: "hourglass")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AquaTheme.cyan)
                                    .accessibilityLabel("Следующее подтверждённое напоминание. " +
                                        ReminderCountdown.message(until: verified, from: timeline.date))
                            } else if case .mismatch = store.reminderQueueStatus {
                                Text("Это прогноз. Очередь iOS требует восстановления.")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        } else {
                            Text("Пока не запланировано")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if paused {
                        Label("Уведомления на паузе до \(AquaDate.time(store.settings.reminderPauseUntil ?? timeline.date, timeZone: store.settings.timeZone)). Возобновить можно в настройках.",
                              systemImage: "pause.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(AquaTheme.muted)
                    } else if night {
                        Label("Сейчас время отдыха. AquaMind не будет беспокоить тебя до начала дня.",
                              systemImage: "moon.zzz")
                            .font(.footnote)
                            .foregroundStyle(AquaTheme.muted)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: queueIcon)
                            .foregroundStyle(queueColor)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(queueHeadline)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(queueColor)
                            Text(queueDetails)
                                .font(.caption)
                                .foregroundStyle(AquaTheme.muted)
                        }
                        Spacer(minLength: 0)
                        Button {
                            store.verifyPendingReminders()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(AquaTheme.cyan)
                                .frame(width: 34, height: 34)
                        }
                        .accessibilityLabel("Проверить уведомления iPhone")
                        .disabled(store.reminderQueueStatus == .checking)
                    }
                    .padding(10)
                    .background(AquaTheme.background.opacity(0.70),
                                in: RoundedRectangle(cornerRadius: 13))

                    if case .mismatch = store.reminderQueueStatus {
                        Button {
                            store.restorePendingReminders()
                        } label: {
                            Label("Восстановить очередь уведомлений",
                                  systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AquaTheme.cyan)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showReminderExplanation.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "brain.head.profile")
                            Text("Почему выбрано это время?")
                            Spacer()
                            Image(systemName: showReminderExplanation ? "chevron.up" : "chevron.down")
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AquaTheme.cyan)
                    }
                    .buttonStyle(.plain)

                    if showReminderExplanation {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(info.headline)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(info.explanation)
                                .font(.subheadline)
                                .foregroundStyle(AquaTheme.muted)
                            Text("За последние 2 часа: \(info.recentMilliliters) мл · За сегодня: \(info.todayMilliliters) мл")
                                .font(.caption)
                                .foregroundStyle(AquaTheme.muted)
                            Text(ReminderPlanner.habitSummary(entries: store.entries,
                                                              settings: store.settings,
                                                              day: timeline.date))
                                .font(.caption)
                                .foregroundStyle(AquaTheme.cyan)
                            Text("Прогноз обновляется после записи напитка. Это ориентир, а не медицинская норма.")
                                .font(.caption2)
                                .foregroundStyle(AquaTheme.muted)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AquaTheme.background.opacity(0.65),
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                } else {
                    Text("Включи уведомления во вкладке «Настройки»")
                        .font(.footnote).foregroundStyle(AquaTheme.muted)
                }
            }
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 20))
            .onChange(of: timeline.date) { _, now in
                // A delivered notification disappears from the pending queue.
                // Refresh in the foreground so the countdown never sticks
                // to an alert that already fired.
                switch store.reminderQueueStatus {
                case .confirmed(let next, _), .postponed(let next):
                    if next <= now { store.restorePendingReminders() }
                default: break
                }
            }
        }
    }

    private var queueIcon: String {
        switch store.reminderQueueStatus {
        case .confirmed: return "checkmark.shield.fill"
        case .postponed: return "clock.fill"
        case .checking: return "arrow.triangle.2.circlepath"
        case .empty: return "moon.zzz"
        case .disabled: return "bell.slash"
        case .permissionRequired, .mismatch: return "exclamationmark.triangle.fill"
        }
    }

    private var queueColor: Color {
        switch store.reminderQueueStatus {
        case .confirmed: return .green
        case .permissionRequired, .mismatch: return .orange
        default: return AquaTheme.cyan
        }
    }

    private var queueHeadline: String {
        switch store.reminderQueueStatus {
        case .confirmed(_, let count): return "Подтверждено iOS · \(count) уведомлений"
        case .postponed: return "Отложенное уведомление"
        case .checking: return "Проверяем очередь iOS…"
        case .empty: return "Очередь уведомлений пуста"
        case .disabled: return "Уведомления отключены"
        case .permissionRequired: return "Нет разрешения на уведомления"
        case .mismatch: return "Расписание требует проверки"
        }
    }

    private var queueDetails: String {
        switch store.reminderQueueStatus {
        case .confirmed: return "Время подтверждено системной очередью iPhone. Доставка зависит от настроек iOS."
        case .postponed: return "iOS приняла временное напоминание после откладывания."
        case .checking: return "Сверяем рассчитанные даты с запросами UserNotifications."
        case .empty: return "Ближайшие обычные напоминания сейчас не требуются."
        case .disabled: return "Включи напоминания в настройках AquaMind."
        case .permissionRequired: return "Открой настройки уведомлений iPhone и разреши AquaMind отправлять сообщения."
        case .mismatch(let expected, let actual):
            return "План: \(expected), в iOS: \(actual). Нажми «Восстановить очередь уведомлений»."
        }
    }

    private var recentPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Последние записи")
                .font(.headline).foregroundStyle(.white)
            if store.todayEntries.isEmpty {
                Text("Сегодня записей пока нет. Начни с первого напитка 💧")
                    .foregroundStyle(AquaTheme.muted).font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16).background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            } else {
                ForEach(store.todayEntries.prefix(5)) { entry in
                    HStack(spacing: 11) {
                        EntryDrinkIcon(entry: entry, size: 32, profiles: store.settings.customDrinks)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AnalyticsDrinkIdentity(entry: entry,
                                      profiles: store.settings.customDrinks).title)
                                .fontWeight(.semibold).foregroundStyle(.white)
                            Text(entry.volumeLabel)
                                .foregroundStyle(AnalyticsDrinkIdentity(
                                    entry: entry, profiles: store.settings.customDrinks).tint)
                        }
                        Spacer()
                        Text(AquaDate.time(entry.date, timeZone: store.settings.timeZone))
                            .foregroundStyle(AquaTheme.muted)
                        Button {
                            entryToDelete = entry
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(AquaTheme.muted)
                                .frame(width: 30, height: 34)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.subheadline)
                    .padding(12).background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 15))
                }
            }
        }
    }
}

private struct AddDrinkSheet: View {
    @EnvironmentObject private var store: HydrationStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var amountFocused: Bool
    @State private var amountText = "250"

    private var parsedAmount: Int? {
        guard let amount = Int(amountText), (25...2000).contains(amount) else { return nil }
        return amount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Group {
                        if let custom = store.activeCustomDrink {
                            PersonalDrinkIcon(name: custom.name, symbol: custom.symbol,
                                              palette: custom.palette, size: 80)
                        } else {
                            DrinkIcon(kind: store.selectedDrink, size: 80)
                        }
                    }
                        .padding(.top, 12)
                    Text(store.selectedDrinkTitle)
                        .font(.title2.bold()).foregroundStyle(.white)
                    HStack(spacing: 8) {
                        TextField("Например, 275", text: $amountText)
                            .keyboardType(.numberPad)
                            .focused($amountFocused)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .accessibilityLabel("Объём в миллилитрах")
                        Text("мл").font(.headline).foregroundStyle(AquaTheme.muted)
                    }
                    .padding(18)
                    .background(AquaTheme.panel, in: RoundedRectangle(cornerRadius: 16))
                    Text("Введи объём от 25 до 2000 мл с клавиатуры.")
                        .font(.footnote).foregroundStyle(AquaTheme.muted)
                    if store.selectedDrink == .broth {
                        Text("Для супа укажи примерный объём именно жидкой части (бульона), а не всей тарелки.")
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AquaTheme.muted)
                    }
                    Button {
                        guard let amount = parsedAmount else { return }
                        store.addSelected(amount)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        dismiss()
                    } label: {
                        Text("Добавить \(parsedAmount ?? 0) мл")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .disabled(parsedAmount == nil)
                    .buttonStyle(.plain)
                    .foregroundStyle(AquaTheme.background)
                    .background(parsedAmount == nil ? AquaTheme.muted :
                        (store.activeCustomDrink.map { PersonalDrinkPalette.tint($0.palette) }
                         ?? store.selectedDrink.tint),
                                in: RoundedRectangle(cornerRadius: 16))
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AquaTheme.background.ignoresSafeArea())
            .navigationTitle("Свой объём")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Готово") { amountFocused = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { amountFocused = true }
    }
}
