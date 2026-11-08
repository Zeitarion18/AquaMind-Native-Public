import AppIntents

// Useful on iPhone, in Shortcuts and through Siri without needing a watchOS app.
// Each action logs water and invokes the existing notification reconciliation.
struct AquaMindAdd150Intent: AppIntent {
    static var title: LocalizedStringResource = "AquaMind: +150 мл воды"
    static var description = IntentDescription("Записать 150 мл воды.")
    static var openAppWhenRun: Bool = false

    @MainActor func perform() async throws -> some IntentResult {
        HydrationStore.shared.add(150)
        await NotificationManager.shared.finishPendingChanges()
        return .result()
    }
}

struct AquaMindAdd250Intent: AppIntent {
    static var title: LocalizedStringResource = "AquaMind: +250 мл воды"
    static var description = IntentDescription("Записать 250 мл воды.")
    static var openAppWhenRun: Bool = false

    @MainActor func perform() async throws -> some IntentResult {
        HydrationStore.shared.add(250)
        await NotificationManager.shared.finishPendingChanges()
        return .result()
    }
}

struct AquaMindAdd350Intent: AppIntent {
    static var title: LocalizedStringResource = "AquaMind: +350 мл воды"
    static var description = IntentDescription("Записать 350 мл воды.")
    static var openAppWhenRun: Bool = false

    @MainActor func perform() async throws -> some IntentResult {
        HydrationStore.shared.add(350)
        await NotificationManager.shared.finishPendingChanges()
        return .result()
    }
}
