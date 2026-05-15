// SettingsView.swift — host scene for the five tabs.
// `TabView` with `.tabViewStyle(.automatic)` so macOS picks the native
// segmented-toolbar idiom. ~580pt wide, taller to give grouped Forms room
// to breathe without internal scrolling.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .environmentObject(store)

            UnitsTab()
                .tabItem { Label("Units", systemImage: "ruler") }
                .environmentObject(store)

            DisplaysTab()
                .tabItem { Label("Displays", systemImage: "display") }
                .environmentObject(store)

            AchievementsTab()
                .tabItem { Label("Achievements", systemImage: "trophy") }
                .environmentObject(store)

            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
                .environmentObject(store)
        }
        .frame(width: 580, height: 560)
        .scenePadding(.minimum)
    }
}

#Preview("Settings") {
    SettingsView().environmentObject(AppStore.preview())
}
