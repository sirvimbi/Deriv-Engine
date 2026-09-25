import SwiftUI

public struct MainTabView: View {
    public init() {}

    public var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }

            HistoryView()
                .tabItem { Label("Transactions", systemImage: "clock.arrow.circlepath") }

            ManualTradeView()
                .tabItem { Label("Manual Trade", systemImage: "hand.tap.fill") }
        }
        .tint(Theme.brandStart)
    }
}
