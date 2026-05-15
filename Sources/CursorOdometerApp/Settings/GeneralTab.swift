// GeneralTab.swift — Launch at Login, menu-bar text label, tracking switches,
// data reset.

import SwiftUI
import CursorOdometerCore

struct GeneralTab: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { store.settings.launchAtLogin = $0
                           AppDelegate.setLaunchAtLogin($0) }
                ))
            } header: {
                Text("Startup")
            } footer: {
                Text("Cursor Odometer lives in the menu bar — by design it stays out of the Dock.")
                    .font(.metaCaption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Toggle("Show distance text in menu bar",
                       isOn: $store.settings.menuBarShowsTextLabel)

                Picker("Format", selection: $store.settings.menuBarLabelFormat) {
                    Label("1.2 km today",
                          systemImage: "cursorarrow.motionlines")
                        .labelStyle(.titleAndIcon)
                        .tag(MenuBarLabelFormat.glyphAndDistance)
                    Text("1.2 km today")
                        .tag(MenuBarLabelFormat.distanceOnly)
                    Text("1.2 km")
                        .tag(MenuBarLabelFormat.distanceWithoutPeriod)
                }
                .pickerStyle(.menu)
                .disabled(!store.settings.menuBarShowsTextLabel)
            }

            Section("Tracking") {
                Toggle("Pause when this Mac is locked",
                       isOn: Binding(
                        get: { !store.settings.countMotionWhileLocked },
                        set: { store.settings.countMotionWhileLocked = !$0 }
                       ))

                Toggle("Count motion across displays",
                       isOn: $store.settings.countCrossDisplayTransitions)
                    .help("By default, the cursor jumping between displays counts as zero distance — only motion within a display is measured.")

                Toggle("Throttle on battery",
                       isOn: $store.settings.battleryThrottleEnabled)
                    .help("Reduces sample rate to extend battery life when unplugged.")

                Toggle("Pause tracking",
                       isOn: Binding(
                        get: { store.isTrackingPaused },
                        set: { store.setTrackingPaused($0) }
                       ))
                    .help("Stops counting cursor distance until you turn this off.")
            }

            Section {
                Button("Reset All Data…", role: .destructive) {
                    confirmAndResetAll()
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Permanently deletes every recorded segment and zeroes the lifetime total. Cannot be undone.")
                    .font(.metaCaption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func confirmAndResetAll() {
        let alert = NSAlert()
        alert.messageText = "Reset all data?"
        alert.informativeText = "This permanently deletes every recorded segment and resets the lifetime total to zero. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset All")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            Task { await store.resetAll() }
        }
    }
}

#Preview("General") {
    GeneralTab()
        .environmentObject(AppStore.preview())
        .frame(width: 580, height: 560)
}
