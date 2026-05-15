// MenuBarLabel.swift — the View used as the MenuBarExtra label. The user
// can opt into a text label with the distance.

import SwiftUI
import CursorOdometerCore

struct MenuBarLabel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if store.settings.menuBarShowsTextLabel {
            DistanceTextLabel()
        } else {
            MenuBarGlyphState(size: 16,
                              state: store.isTrackingPaused ? .paused : .tracking)
                .accessibilityLabel(accessibilitySummary)
        }
    }

    private var accessibilitySummary: String {
        let formatter = DistanceFormatter(customUnits: store.customUnits)
        let f = formatter.format(store.todayDistance, in: store.activeHeroUnit)
        return "Cursor Odometer. \(f.numberText) \(f.unitLabel) today."
    }
}

/// Glyph + tabular SF Mono distance text.
private struct DistanceTextLabel: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let formatter = DistanceFormatter(customUnits: store.customUnits)
        let f = formatter.format(store.todayDistance, in: store.activeHeroUnit)

        HStack(spacing: 5) {
            switch store.settings.menuBarLabelFormat {
            case .glyphAndDistance:
                MenuBarGlyph(size: 14)
                Text("\(f.numberText) \(f.unitLabel) today")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .monospacedDigit()
            case .distanceOnly:
                Text("\(f.numberText) \(f.unitLabel) today")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .monospacedDigit()
            case .distanceWithoutPeriod:
                Text("\(f.numberText) \(f.unitLabel)")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("Cursor Odometer. \(f.numberText) \(f.unitLabel) today.")
    }
}

#Preview("Glyph only") {
    MenuBarLabel()
        .environmentObject(AppStore.preview())
        .padding(Space.s2)
        .background(Color.surface)
}

#Preview("Text label") {
    let store = AppStore.preview()
    var settings = SettingsValues.defaults
    settings.menuBarShowsTextLabel = true
    settings.menuBarLabelFormat = .glyphAndDistance
    store.settings = settings
    return MenuBarLabel()
        .environmentObject(store)
        .padding(Space.s2)
        .background(Color.surface)
}
