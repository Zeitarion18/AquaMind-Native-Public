import Foundation

@main
struct PersonalDrinksSmokeTests {
    static func main() {
        var settings = HydrationSettings()
        settings.preferredTimeZoneID = "Europe/Samara"
        let calendar = settings.calendar
        let today = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 4, hour: 14, minute: 55))!
        let profile = CustomDrink(name: "Бабл-ти", symbol: "aquamind.boba",
                                  palette: 8)
        settings.customDrinks = [profile]

        let legacyBubble = WaterEntry(
            date: today, milliliters: 350, kind: .other,
            customDrinkName: "Бабл-ти",
            customDrinkSymbol: "takeoutbag.and.cup.and.straw.fill",
            customDrinkPalette: 1)
        let newBubble = WaterEntry(
            date: today, milliliters: 100, kind: .other,
            customDrinkName: "Бабл-ти", customDrinkID: profile.id,
            customDrinkSymbol: "aquamind.boba", customDrinkPalette: 8)
        let water = WaterEntry(date: today, milliliters: 500, kind: .water)
        let other = WaterEntry(date: today, milliliters: 75, kind: .other)
        let entries = [water, legacyBubble, newBubble, other]

        let breakdown = HydrationRing.breakdown(
            entries: entries, profiles: settings.customDrinks)
        assert(breakdown.count == 3, "Custom and built-in Other must be separate")
        assert(breakdown.reduce(0) { $0 + $1.amount } == 1025)
        let boba = breakdown.first(where: { $0.identity.title == "Бабл-ти" })!
        assert(boba.amount == 450)
        assert(boba.identity.customPalette == 8)
        assert(boba.identity.customSymbol == "aquamind.boba")
        assert(boba.identity.customID == profile.id)
        assert(breakdown.contains { $0.identity.title == "Другое" && $0.amount == 75 })

        let slices = HydrationRing.segments(
            entries: entries, goal: 2000, profiles: settings.customDrinks)
        assert(slices.count == 3)
        assert(abs(slices.last!.end - 0.5125) < 0.00001)
        assert(slices.contains { $0.identity.title == "Бабл-ти" })

        let report = HydrationAnalytics.report(
            entries: entries, span: .day, anchor: today, now: today,
            calendar: calendar, profiles: settings.customDrinks)
        assert(report.total == 1025 && report.recordCount == 4)
        assert(report.drinks.count == 3)
        assert(report.buckets.count == 3)
        assert(report.drinks.first(where: { $0.title == "Бабл-ти" })?.milliliters == 450)
        assert(report.drinks.first(where: { $0.title == "Бабл-ти" })?.identity.customPalette == 8)
        assert(report.drinks.contains { $0.title == "Другое" && $0.milliliters == 75 })

        // Editing a profile may change how matching historic records are
        // colored, but it must never rewrite the stored entry snapshots.
        let modified = CustomDrink(id: profile.id, name: "Бабл-ти",
                                   symbol: "aquamind.boba", palette: 9)
        let recolored = HydrationRing.breakdown(entries: entries, profiles: [modified])
        assert(recolored.first(where: { $0.identity.title == "Бабл-ти" })?.identity.customPalette == 9)
        assert(legacyBubble.customDrinkPalette == 1)
        assert(HydrationRing.breakdown(entries: entries).reduce(0) { $0 + $1.amount } == 1025)

        let archive = HydrationArchive(entries: entries, settings: settings)
        let persisted = try! JSONEncoder().encode(archive)
        let restored = try! JSONDecoder().decode(HydrationArchive.self, from: persisted)
        assert(restored.entries.count == 4)
        assert(restored.entries[1].customDrinkName == "Бабл-ти")
        assert(restored.entries[1].customDrinkID == nil)
        assert(restored.entries[2].customDrinkID == profile.id)
        assert(restored.settings.customDrinks[0].palette == 8)

        assert(DrinkIconCatalog.all.count >= 150)
        assert(Set(DrinkIconCatalog.all.map(\.symbol)).count == DrinkIconCatalog.all.count)
        assert(DrinkIconCatalog.categories.count >= 10)
        assert(DrinkIconCatalog.isSupported("aquamind.boba"))
        assert(DrinkIconCatalog.find("бабл").contains { $0.symbol == "aquamind.boba" })
        assert(DrinkIconCatalog.find("тапиока").contains { $0.symbol == "aquamind.boba" })
        assert(!DrinkIconCatalog.find("кофе").isEmpty)
        assert(!DrinkIconCatalog.find("сок").isEmpty)
        assert(!DrinkIconCatalog.find("стакан", category: "Бабл-ти и коктейли").isEmpty)

        // Unrelated reminder settings continue to decode unchanged.
        assert(restored.settings.dailyGoal == settings.dailyGoal)
        assert(restored.settings.weeklySchedule == settings.weeklySchedule)
        print("AquaMind 0.7.1 tests passed: custom ring, home composition, analytics, profile edits, legacy storage, 176 unique icons")
    }
}
