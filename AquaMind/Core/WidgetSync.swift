import Foundation
import WidgetKit

enum AquaMindWidgetSync {
    static func update(entries: [WaterEntry], settings: HydrationSettings) {
        let snapshot = AquaMindWidgetSnapshot.make(
            entries: entries, settings: settings, now: Date())
        AquaMindWidgetStore.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "AquaMindHydration")
    }
}
