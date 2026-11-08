import Foundation

/// One separate arc per drink identity, including individually named custom drinks.
struct HydrationRingSlice: Identifiable, Equatable {
    let identity: AnalyticsDrinkIdentity
    let start: Double
    let end: Double

    var id: String { identity.id }
    /// Kept for compatibility with existing ring tests and built-in drink logic.
    var kind: DrinkKind { identity.kind }
}

/// The same grouping identity is used by Aurora Ring, home breakdown and charts.
enum HydrationRing {
    static func breakdown(entries: [WaterEntry],
                          profiles: [CustomDrink] = [])
        -> [(identity: AnalyticsDrinkIdentity, amount: Int)] {
        var volumes: [AnalyticsDrinkIdentity: Int] = [:]
        for entry in entries where entry.milliliters > 0 {
            let identity = AnalyticsDrinkIdentity(entry: entry, profiles: profiles)
            volumes[identity, default: 0] += entry.milliliters
        }
        return volumes.keys.sorted { lhs, rhs in
            let li = DrinkKind.allCases.firstIndex(of: lhs.kind) ?? 100
            let ri = DrinkKind.allCases.firstIndex(of: rhs.kind) ?? 100
            if li != ri { return li < ri }
            return lhs.id < rhs.id
        }.compactMap { identity in
            guard let amount = volumes[identity], amount > 0 else { return nil }
            return (identity: identity, amount: amount)
        }
    }

    static func segments(entries: [WaterEntry], goal: Int,
                         profiles: [CustomDrink] = []) -> [HydrationRingSlice] {
        let volumes = breakdown(entries: entries, profiles: profiles)
        let total = volumes.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }

        // Preserve dark unused arc below the goal. Over the goal, normalize
        // to total so that the last personal drink is never clipped.
        let scale = Double(max(max(goal, 1), total))
        var position = 0.0
        return volumes.map { item in
            let start = position
            position = min(1, position + Double(item.amount) / scale)
            return HydrationRingSlice(identity: item.identity,
                                      start: start, end: position)
        }
    }
}
