// PerDisplayBar.swift — stacked horizontal bar showing per-display share of
// distance. "Lean stacked, not pie." With 3+ displays the
// stacked bar is much more legible than slicing a pie.

import SwiftUI
import CursorOdometerCore

struct PerDisplayBar: View {
    let totals: [DisplayUUID: Distance]
    let displays: [DisplayInfo]
    var height: CGFloat = 28

    @Environment(\.accessibilityShowButtonShapes) private var increasedContrast

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            GeometryReader { geo in
                let total = totals.values.reduce(Distance.zero, +).meters
                let safeTotal = max(total, 0.001)
                HStack(spacing: 0) {
                    ForEach(Array(orderedEntries), id: \.0) { uuid, distance in
                        let pct = distance.meters / safeTotal
                        Rectangle()
                            .fill(color(for: uuid))
                            .frame(width: max(2, geo.size.width * pct))
                            .accessibilityElement()
                            .accessibilityLabel("\(name(for: uuid)): \(Int((pct * 100).rounded())) percent")
                    }
                }
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .strokeBorder(Color.hairline, lineWidth: increasedContrast ? 1.5 : 1)
                )
            }
            .frame(height: height)

            // Legend
            FlowLegend(items: orderedEntries.map { uuid, dist in
                LegendItem(
                    color: color(for: uuid),
                    label: name(for: uuid),
                    valueText: format(dist)
                )
            })
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Per-display distance breakdown")
    }

    private var orderedEntries: [(DisplayUUID, Distance)] {
        // Sort by distance descending so the largest bar segment is leftmost.
        totals.sorted(by: { $0.value > $1.value }).map { ($0.key, $0.value) }
    }

    private func name(for uuid: DisplayUUID) -> String {
        displays.first(where: { $0.uuid == uuid })?.displayName ?? uuid.rawValue
    }

    private func color(for uuid: DisplayUUID) -> Color {
        // Deterministic palette: primary brand, lifetime brand, then complementary
        // hues. Same display always gets the same color across renders.
        let palette: [Color] = [
            .colorPrimary,
            .colorLifetime,
            .colorAchievementGold,
            .colorOnTrack
        ]
        let index = abs(uuid.rawValue.hashValue) % palette.count
        return palette[index]
    }

    private func format(_ d: Distance) -> String {
        if d.meters >= 1000 {
            return String(format: "%.2f km", d.kilometers)
        } else {
            return String(format: "%.0f m", d.meters)
        }
    }
}

// MARK: - Legend

private struct LegendItem: Identifiable {
    let id = UUID()
    let color: Color
    let label: String
    let valueText: String
}

private struct FlowLegend: View {
    let items: [LegendItem]

    var body: some View {
        // Use a wrap layout via HStack with adaptive layout for compactness.
        HStack(spacing: Space.s4) {
            ForEach(items) { item in
                HStack(spacing: Space.s1) {
                    Circle().fill(item.color).frame(width: 8, height: 8)
                    Text(item.label).font(.metaCaption)
                    Text(item.valueText).font(.metaCaption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer()
        }
    }
}

// MARK: - Previews

#Preview("Per-display stacked bar") {
    PerDisplayBar(
        totals: [
            DisplayUUID("builtin-retina"): .meters(742),
            DisplayUUID("studio-display"): .meters(505),
            DisplayUUID("sidecar-ipad"): .meters(120)
        ],
        displays: [
            .previewBuiltin,
            .previewStudio,
            DisplayInfo(uuid: DisplayUUID("sidecar-ipad"),
                        displayName: "iPad Sidecar",
                        frame: CGRect(x: 0, y: 0, width: 1366, height: 1024),
                        physicalSize: .zero,
                        backingScaleFactor: 2,
                        isPrimary: false)
        ]
    )
    .frame(width: 480)
    .padding()
    .background(Color.surface)
}
