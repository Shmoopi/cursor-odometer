// DisplaysTab.swift — per-display list with inline name, metadata,
// today's distance, and a track toggle.

import SwiftUI
import CursorOdometerCore

struct DisplaysTab: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Form {
            Section {
                ForEach(store.displays, id: \.uuid) { display in
                    DisplayRow(display: display)
                }
            } header: {
                Text("Attached Displays")
            } footer: {
                Text("If a display reports zero physical size — common with Sidecar, AirPlay, and some HDMI dongles — Cursor Odometer falls back to a 96 DPI estimate.")
                    .font(.metaCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisplayRow: View {
    @EnvironmentObject private var store: AppStore
    let display: DisplayInfo

    var body: some View {
        let isTracked = store.settings.trackedDisplays.isEmpty
            || store.settings.trackedDisplays.contains(display.uuid)
        let dist = store.perDisplayToday[display.uuid] ?? .zero

        HStack(alignment: .center, spacing: Space.s2) {
            Image(systemName: "display")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(display.isPrimary ? Color.colorPrimary : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill((display.isPrimary ? Color.colorPrimary : .secondary)
                        .opacity(0.10))
                )

            Text(display.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            if display.isPrimary {
                Badge(text: "Primary", tint: Color.colorPrimary)
            }
            if display.hasEstimatedSize {
                Badge(text: "Estimated", tint: .secondary)
            }

            // Metadata cluster — separators hug their text so the whole group
            // stays at its natural width and won't ellipsize.
            HStack(spacing: Space.s1) {
                InlineSeparator()
                MetaText(text: "\(Int(display.frame.width))×\(Int(display.frame.height))")

                if !display.hasEstimatedSize {
                    InlineSeparator()
                    MetaText(text: String(format: "%.0f×%.0f mm",
                                          display.physicalSize.width,
                                          display.physicalSize.height))
                }
            }
            .fixedSize()

            Spacer(minLength: Space.s2)

            Text(formatDistance(dist))
                .font(.numeralInline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()

            Toggle("", isOn: Binding(
                get: { isTracked },
                set: { newVal in
                    if newVal {
                        store.settings.trackedDisplays.insert(display.uuid)
                    } else {
                        store.settings.trackedDisplays.remove(display.uuid)
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .help(isTracked ? "Tracking this display" : "Not tracking this display")
        }
        .padding(.vertical, 2)
    }

    private func formatDistance(_ d: Distance) -> String {
        if d.meters >= 1000 { return String(format: "%.2f km today", d.kilometers) }
        return String(format: "%.0f m today", d.meters)
    }
}

private struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
            .fixedSize()
    }
}

private struct InlineSeparator: View {
    var body: some View {
        Text("·")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

private struct MetaText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.metaCaption)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .lineLimit(1)
    }
}

#Preview("Displays tab — built-in + Studio") {
    DisplaysTab()
        .environmentObject(AppStore.preview())
        .frame(width: 580, height: 560)
}
