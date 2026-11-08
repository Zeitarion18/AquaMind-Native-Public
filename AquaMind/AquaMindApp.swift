import SwiftUI

@main
@MainActor
struct AquaMindApp: App {
    @UIApplicationDelegateAdaptor(AquaMindAppDelegate.self) private var appDelegate
    @StateObject private var store = HydrationStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .onAppear { store.refresh() }
                .onOpenURL { url in store.handleWidgetURL(url) }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active { store.refresh() }
                }
        }
    }
}
