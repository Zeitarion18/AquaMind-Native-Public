import AppIntents

/// Add these actions to the iOS Shortcuts automation for Sleep Focus:
///  - turning Sleep Focus on  -> AquaMind: Лёг спать
///  - turning Sleep Focus off -> AquaMind: Проснулся
/// Focus is a user signal, NOT measured sleep onset.
struct AquaMindStartSleepIntent: AppIntent {
    static var title: LocalizedStringResource = "AquaMind: Лёг спать"
    static var description = IntentDescription(
        "Приостанавливает обычные напоминания AquaMind до следующего пробуждения.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        HydrationStore.shared.beginSleep()
        await NotificationManager.shared.finishPendingChanges()
        return .result()
    }
}

struct AquaMindWakeUpIntent: AppIntent {
    static var title: LocalizedStringResource = "AquaMind: Проснулся"
    static var description = IntentDescription(
        "Завершает паузу сна и переносит начало сегодняшнего дня на текущее время.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        HydrationStore.shared.wakeUp()
        await NotificationManager.shared.finishPendingChanges()
        return .result()
    }
}
