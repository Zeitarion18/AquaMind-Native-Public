import SwiftUI
import UIKit
import UserNotifications

/// Diagnostic information from UserNotifications is NOT evidence of delivery.
private struct DiagnosticRow: Identifiable {
    let title: String
    let value: String
    var id: String { title }
}

struct NotificationDiagnosticsView: View {
    @EnvironmentObject private var store: HydrationStore
    @Environment(\.openURL) private var openURL
    @State private var rows: [DiagnosticRow] = []
    @State private var futureDates: [Date] = []
    @State private var details: [String] = []
    @State private var queueSummary = "Проверяем…"
    @State private var statusMessage: String?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                ForEach(rows) { row in
                    LabeledContent(row.title, value: row.value)
                }
                Button {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                } label: {
                    Label("Открыть настройки уведомлений iOS",
                          systemImage: "gearshape.2")
                }
            } header: {
                Text("Разрешения и отображение")
            } footer: {
                Text("Звуки и экран блокировки зависят от настроек iPhone.")
            }

            Section {
                Label(queueSummary, systemImage: "checkmark.shield")
                    .foregroundStyle(AquaTheme.cyan)
                ForEach(Array(futureDates.prefix(8)), id: \.self) { date in
                    HStack {
                        Text(AquaDate.fullDate(
                            date, timeZone: store.settings.timeZone))
                            .font(.footnote)
                        Spacer()
                        Text(AquaDate.time(
                            date, timeZone: store.settings.timeZone))
                            .font(.footnote.weight(.semibold))
                    }
                }
            } header: {
                Text("Реальная очередь iPhone")
            } footer: {
                Text("Очередь подтверждает планирование, но не фактическое появление баннера, звук или вибрацию.")
            }

            Section("Возможные причины неполучения") {
                ForEach(details, id: \.self) { detail in
                    Label(detail, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(AquaTheme.muted)
                }
            }

            Section {
                Button {
                    Task { await refresh(replan: false) }
                } label: {
                    Label("Перепроверить", systemImage: "arrow.clockwise")
                }
                .disabled(busy)
                Button {
                    Task { await refresh(replan: true) }
                } label: {
                    Label("Перепланировать уведомления",
                          systemImage: "calendar.badge.clock")
                }
                .disabled(busy)
                Button {
                    Task { await testReminder() }
                } label: {
                    Label("Тест через 1 минуту", systemImage: "bell.badge")
                }
                .disabled(busy)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote).foregroundStyle(AquaTheme.muted)
                }
            } footer: {
                Text("Для проверки теста заблокируй iPhone и дождись назначенного времени. Если включена сводка или фокусирование, iOS может показать уведомление позже.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(AquaTheme.background)
        .navigationTitle("Диагностика iOS")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh(replan: false) }
    }

    @MainActor private func refresh(replan: Bool) async {
        guard !busy else { return }
        busy = true
        if replan {
            NotificationManager.shared.schedule(
                entries: store.entries, settings: store.settings)
        }
        await NotificationManager.shared.finishPendingChanges()
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings()
        let requests = await center.pendingNotificationRequests()
        let now = Date()
        let desired = ReminderPlanner.upcomingDates(
            entries: store.entries, settings: store.settings, now: now)
        let actual = requests.filter { $0.identifier.hasPrefix("am_reminder_") }
            .compactMap {
                ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            }.filter { $0 > now }.sorted()
        let snooze = requests.filter { $0.identifier.hasPrefix("am_snooze_") }
            .compactMap {
                ($0.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
            }.filter { $0 > now }.sorted()
        futureDates = actual
        let matches = NotificationQueueComparison.matches(planned: desired, queued: actual)
        queueSummary = "В очереди \(actual.count), ожидается \(desired.count)" +
            (matches ? " · совпадает" : " · нужна проверка")
        if let next = snooze.first {
            queueSummary += " · есть отложенное"
            futureDates = ([next] + futureDates).sorted()
        }
        let status = authorization.authorizationStatus
        let permitted = status == .authorized || status == .provisional
        let statusTitle: String
        switch status {
        case .authorized: statusTitle = "Разрешено"
        case .provisional: statusTitle = "Разрешено тихо"
        case .denied: statusTitle = "Запрещено"
        case .notDetermined: statusTitle = "Ещё не запрашивалось"
        case .ephemeral: statusTitle = "Временное разрешение"
        @unknown default: statusTitle = "Неизвестно"
        }
        rows = [
            DiagnosticRow(title: "Уведомления", value: statusTitle),
            DiagnosticRow(title: "Оповещения",
                          value: settingLabel(authorization.alertSetting)),
            DiagnosticRow(title: "Звук",
                          value: settingLabel(authorization.soundSetting)),
            DiagnosticRow(title: "Экран блокировки",
                          value: settingLabel(authorization.lockScreenSetting)),
            DiagnosticRow(title: "Сводка уведомлений",
                          value: settingLabel(authorization.scheduledDeliverySetting))
        ]
        var advice: [String] = []
        if !store.settings.remindersEnabled {
            advice.append("Умные напоминания отключены в AquaMind.")
        }
        if !permitted {
            advice.append("Проверь разрешение AquaMind в настройках iPhone.")
        }
        if status == .provisional {
            advice.append("Тихое разрешение может не показывать баннер и звук.")
        }
        if permitted && authorization.alertSetting == .disabled {
            advice.append("Баннеры уведомлений отключены.")
        }
        if permitted && authorization.lockScreenSetting == .disabled {
            advice.append("Оповещения не будут отображаться на экране блокировки.")
        }
        if permitted && authorization.soundSetting == .disabled {
            advice.append("Звук выключен, но это не означает отсутствие уведомления.")
        }
        if permitted && authorization.scheduledDeliverySetting == .enabled {
            advice.append("Сводка уведомлений может отложить показ.")
        }
        if permitted && store.settings.remindersEnabled && !matches {
            advice.append("Число или время в очереди отличается от расчёта. Попробуй перепланировать.")
        }
        advice.append("Фокусирование, режим «Без звука» и перенаправление на Apple Watch могут менять способ показа. AquaMind не умеет подтверждать прочтение уведомления.")
        details = advice
        busy = false
    }

    private func settingLabel(_ value: UNNotificationSetting) -> String {
        switch value {
        case .enabled: return "Включено"
        case .disabled: return "Выключено"
        default: return "Недоступно"
        }
    }

    @MainActor private func testReminder() async {
        guard !busy else { return }
        busy = true
        do {
            let due = try await NotificationManager.shared.scheduleOneMinuteTest()
            let timeText = AquaDate.time(due, timeZone: store.settings.timeZone)
            statusMessage = "Запрос принят iOS на \(timeText). Получение проверь вручную."
        } catch {
            statusMessage = "Не удалось поставить тест: \(error.localizedDescription)"
        }
        busy = false
        await refresh(replan: false)
    }
}
