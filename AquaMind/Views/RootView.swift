import SwiftUI

enum AquaTheme {
    static let background = Color(red: 0.035, green: 0.075, blue: 0.13)
    static let panel = Color(red: 0.075, green: 0.13, blue: 0.21)
    static let cyan = Color(red: 0.28, green: 0.87, blue: 0.96)
    static let blue = Color(red: 0.15, green: 0.48, blue: 0.96)
    static let muted = Color(red: 0.65, green: 0.75, blue: 0.82)
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Сегодня", systemImage: "drop.fill") }
            HistoryView()
                .tabItem { Label("История", systemImage: "chart.bar.fill") }
            SettingsView()
                .tabItem { Label("Настройки", systemImage: "gearshape.fill") }
        }
        .tint(AquaTheme.cyan)
    }
}
