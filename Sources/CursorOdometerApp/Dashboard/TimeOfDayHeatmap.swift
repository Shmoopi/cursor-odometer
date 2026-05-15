// TimeOfDayHeatmap.swift — 24×7 heatmap. Computed on-the-fly
// from `motion_segment` rows for the last 24h plus daily aggregates beyond
// that. Cell color encodes intensity; AA-contrast tooltip on hover.

import SwiftUI
import CursorOdometerCore

struct TimeOfDayHeatmap: View {
    /// 7 rows (days of week) × 24 columns (hours). Values 0…1 where 1 is the
    /// max in the dataset. View-models normalise before passing in.
    let intensities: [[Double]]
    var rowLabels: [String] = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Hour ticks header
            HStack(spacing: 2) {
                Spacer().frame(width: 14)
                ForEach(0..<24, id: \.self) { hour in
                    Text(hour % 6 == 0 ? "\(hour)" : "")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)

            ForEach(0..<min(intensities.count, 7), id: \.self) { row in
                HStack(spacing: 2) {
                    Text(rowLabels[row])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, alignment: .leading)
                    ForEach(0..<24, id: \.self) { col in
                        let v = intensities[row][col]
                        Cell(intensity: v, day: rowLabels[row], hour: col)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Time-of-day heatmap, 24 hours by 7 days")
    }
}

private struct Cell: View {
    let intensity: Double
    let day: String
    let hour: Int

    @State private var hovering = false

    var body: some View {
        let color = Color.colorPrimary.opacity(0.10 + max(0, min(1, intensity)) * 0.85)
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(maxWidth: .infinity)
            .frame(height: 14)
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(hovering ? Color.colorPrimary : .clear, lineWidth: 1)
            )
            .help("\(day), \(hour):00 — \(Int((intensity * 100).rounded()))% of peak")
            .accessibilityLabel("\(day), \(hour) hundred hours, \(Int((intensity * 100).rounded())) percent of peak")
            .onHover { hovering = $0 }
            .animation(.hover, value: hovering)
    }
}

#Preview("Time-of-day heatmap") {
    let rng = (0..<7).map { row in
        (0..<24).map { col in
            // Shape: gentle hump centered at noon, weekends quieter.
            let isWeekend = row >= 5
            let base = max(0, sin(Double(col) * .pi / 24))
            let multiplier = isWeekend ? 0.4 : 1.0
            return base * multiplier
        }
    }
    return TimeOfDayHeatmap(intensities: rng)
        .frame(width: 480, height: 140)
        .padding()
        .background(Color.surface)
}
