import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: HydrationStore
    @AppStorage("AquaMind.auroraShimmer") private var auroraShimmer = true
    @AppStorage("AquaMind.auroraGlow") private var auroraGlow = true
    @AppStorage("AquaMind.auroraFill") private var auroraFill = true
    @AppStorage("AquaMind.auroraBubbles") private var auroraBubbles = true

    private let zones: [(String, String)] = [
        ("system", "Авто (iPhone)"),
        ("Europe/Moscow", "Москва"),
        ("Europe/Samara", "Самара / Ижевск"),
        ("Asia/Yekaterinburg", "Екатеринбург"),
        ("Europe/Amsterdam", "Амстердам"),
        ("Asia/Tokyo", "Токио"),
        ("America/New_York", "Нью-Йорк")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Label("Дневная цель жидкости", systemImage: "target")
                        Spacer()
                        Text("\(store.settings.dailyGoal) мл")
                            .foregroundStyle(AquaTheme.cyan)
                    }
                    Stepper("Изменить цель", value: Binding(
                        get: { store.settings.dailyGoal },
                        set: { store.setGoal($0) }),
                            in: 250...5000, step: 250)
                } header: { Text("Дневная цель") }
                footer: { Text("Цель — ориентир по объёму жидкости из напитков и бульона. Это не медицинская норма: не нужно пить через силу.") }

                Section {
                    Toggle(isOn: Binding(get: { store.settings.remindersEnabled },
                                         set: { store.setReminders($0) })) {
                        Label("Умные напоминания", systemImage: "bell")
                    }
                    .tint(AquaTheme.cyan)
                    if store.settings.remindersEnabled {
                        Stepper("Минимальная пауза: \(store.settings.minimumReminderMinutes) мин",
                                value: Binding(
                                    get: { store.settings.minimumReminderMinutes },
                                    set: { store.setMinimumReminderMinutes($0) }),
                                in: 30...240, step: 15)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Гибкий интервал после напитка")
                                .font(.subheadline.weight(.medium))
                            ForEach([50, 150, 250, 500], id: \.self) { amount in
                                HStack {
                                    Text("\(amount) мл")
                                    Spacer()
                                    Text("через \(ReminderPlanner.intervalMinutes(after: amount, minimum: store.settings.minimumReminderMinutes)) мин")
                                        .foregroundStyle(AquaTheme.cyan)
                                }
                                .font(.footnote)
                            }
                            Text("Это примеры для одного напитка. Несколько напитков за 2 часа учитываются вместе.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        NavigationLink {
                            WeeklyScheduleView()
                        } label: {
                            Label("Расписание по дням недели", systemImage: "calendar.badge.clock")
                        }
                        HStack {
                            Text("Сегодня")
                            Spacer()
                            Text(todayScheduleLabel)
                                .foregroundStyle(AquaTheme.cyan)
                                .font(.subheadline)
                        }
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.shield")
                                .foregroundStyle(AquaTheme.cyan)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Проверка расписания iPhone").font(.subheadline.weight(.medium))
                                Text(queueSettingsSummary)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Button {
                                store.verifyPendingReminders()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Проверить очередь напоминаний")
                        }

                        Button {
                            store.scheduleTestReminder()
                        } label: {
                            Label("Тестовое уведомление через 1 минуту", systemImage: "bell.badge")
                                .foregroundStyle(AquaTheme.cyan)
                        }
                        .disabled(store.testReminderStatus == .scheduling)

                        switch store.testReminderStatus {
                        case .idle:
                            EmptyView()
                        case .scheduling:
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Проверяем и планируем уведомление…")
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 6)
                        case .scheduled(let due):
                            Label {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Тестовое уведомление запланировано!")
                                        .fontWeight(.semibold)
                                    Text("Примерно в \(AquaDate.time(due, timeZone: store.settings.timeZone)). Можешь заблокировать iPhone.")
                                        .font(.footnote)
                                }
                            } icon: {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            .foregroundStyle(Color.green)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        case .failed(let reason):
                            Label {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("Не удалось запланировать тест")
                                        .fontWeight(.semibold)
                                    Text(reason)
                                        .font(.footnote)
                                }
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .foregroundStyle(Color.orange)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else if !store.notificationsAllowed {
                        Text("Разреши уведомления, чтобы iPhone мог напоминать о воде.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Открыть настройки уведомлений iPhone") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } header: { Text("Напоминания") }
                footer: { Text("Расписание отдельно для каждого дня недели. Ручные кнопки «Лёг спать» и «Проснулся» корректируют сегодняшний режим. Автоматизации «Команд» могут запускать те же действия по режиму фокусирования «Сон», но это не датчик фактического сна.") }

                Section {
                    NavigationLink {
                        NotificationDiagnosticsView()
                    } label: {
                        Label("Диагностика уведомлений iPhone",
                              systemImage: "checkmark.shield.fill")
                    }
                    Text("Разрешения, звуки, экран блокировки, сводка iOS и фактическая очередь. Можно провести повторную проверку и тест на одну минуту.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Проверка напоминаний") }

                Section("Управление сном") {
                    HStack(spacing: 12) {
                        Button("Лёг спать") { store.beginSleep() }
                            .buttonStyle(.bordered)
                            .disabled(store.settings.isManualSleepActive(at: Date()))
                        Button("Проснулся") { store.wakeUp() }
                            .buttonStyle(.borderedProminent)
                            .tint(AquaTheme.cyan)
                    }
                    Text("Через приложение «Команды» можно также привязать действия AquaMind «Лёг спать» и «Проснулся» к включению и выключению фокусирования «Сон». Эти команды нужно настроить один раз на iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Label("Быстрые команды +150, +250 и +350 мл", systemImage: "shortcuts")
                    Text("Найди действия AquaMind в приложении «Команды» и добавь их на главный экран или на Apple Watch. Они добавляют воду в историю без отдельного watchOS-приложения.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Настоящие виджеты iPhone требуют расширения WidgetKit и доступа App Groups. В экспериментальной сборке 0.5.0 есть виджет баланса и кнопки, открывающие AquaMind для добавления воды.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Виджеты и часы") }
                Section {
                    NavigationLink {
                        PersonalizationView()
                    } label: {
                        Label("Мои напитки, стаканы и быстрые кнопки",
                              systemImage: "slider.horizontal.3")
                    }
                    Text("Настрой любимые объёмы, добавь собственные напитки, кружки и бутылки. Примерные записи в истории отмечаются знаком ≈.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Personalization") }

                Section("Часовой пояс") {
                    Picker("Часовой пояс", selection: Binding(
                        get: { store.settings.preferredTimeZoneID },
                        set: { store.setTimeZone($0) })) {
                            ForEach(zones, id: \.0) { zone in
                                Text(zone.1).tag(zone.0)
                            }
                        }
                    Text("По умолчанию используется часовой пояс самого iPhone — геолокация не требуется.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    Toggle(isOn: $auroraBubbles) {
                        Label("Живые пузырьки", systemImage: "circle.hexagongrid.fill")
                    }
                    .tint(AquaTheme.cyan)
                    Toggle(isOn: $auroraShimmer) {
                        Label("Плавные переливающиеся блики", systemImage: "sparkles")
                    }
                    .tint(AquaTheme.cyan)
                    Toggle(isOn: $auroraGlow) {
                        Label("Мягкое неоновое свечение", systemImage: "sun.max")
                    }
                    .tint(AquaTheme.cyan)
                    Toggle(isOn: $auroraFill) {
                        Label("Анимация заполнения", systemImage: "circle.dotted.circle")
                    }
                    .tint(AquaTheme.cyan)
                } header: {
                    Text("Aurora Ring")
                } footer: {
                    Text("Края цветных сегментов мягко закруглены. Пузырьки появляются из-за границ, но видны строго внутри своей цветной полосы. Их можно отключить отдельно; анимации останавливаются в фоне и при системном «Уменьшении движения».")
                }

                Section("О приложении") {
                    LabeledContent("Версия", value: "0.7.5 Aurora Bubble Mask Fix")
                    LabeledContent("Платформа", value: "SwiftUI · iOS 17+")
                    Text("Напитки учитываются по введённому объёму. Для супа указывай только жидкую часть.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Label("Данные хранятся локально на iPhone", systemImage: "lock.shield")
                        .foregroundStyle(AquaTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AquaTheme.background)
            .navigationTitle("Настройки")
            .onAppear { store.refresh() }
        }
    }

    private var todayScheduleLabel: String {
        let schedule = store.settings.schedule(for:
            store.settings.calendar.component(.weekday, from: Date()))
        return "\(schedule.wakeLabel)–\(schedule.sleepLabel)"
    }

    private var queueSettingsSummary: String {
        switch store.reminderQueueStatus {
        case .disabled: return "Выключено"
        case .checking: return "Проверяем…"
        case .confirmed(let next, let count):
            return "\(count) в очереди · ближайшее \(AquaDate.time(next, timeZone: store.settings.timeZone))"
        case .postponed(let next):
            return "Отложено до \(AquaDate.time(next, timeZone: store.settings.timeZone))"
        case .empty: return "Очередь пуста"
        case .permissionRequired: return "Нет разрешения iOS"
        case .mismatch(let expected, let actual):
            return "Не совпадает: ожидалось \(expected), в iOS \(actual)"
        }
    }
}
