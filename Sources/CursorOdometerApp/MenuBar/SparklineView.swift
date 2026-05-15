// SparklineView.swift — last-7-days bar graph for the popover.
// 24pt tall, 7 bars, accent color, draws in over 400ms with 20ms stagger
// (instant under Reduce Motion). Each bar is individually accessible.

import SwiftUI
import CursorOdometerCore

struct SparklineView: View {
    let values: [DailyAggregate]            // ascending; oldest first
    var height: CGFloat = 24
    var unitLabel: String = "today"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityShowButtonShapes) private var increasedContrast
    @State private var hasAnimatedIn: Bool = false

    var body: some View {
        let maxVal = values.map { $0.distance.meters }.max() ?? 1
        let safeMax = max(maxVal, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, agg in
                let h = (agg.distance.meters / safeMax) * height
                Capsule(style: .continuous)
                    .fill(Color.colorPrimary)
                    .frame(width: 8, height: max(2, hasAnimatedIn ? CGFloat(h) : 2))
                    .accessibilityElement()
                    .accessibilityLabel(label(for: agg, index: index))
                    .animation(
                        MotionToken.sparkline(reduceMotion: reduceMotion).map {
                            $0.delay(MotionToken.sparklineStagger(reduceMotion: reduceMotion) * Double(index))
                        } ?? .linear(duration: 0),
                        value: hasAnimatedIn
                    )
            }
        }
        .frame(height: height, alignment: .bottom)
        .onAppear {
            if reduceMotion {
                hasAnimatedIn = true
            } else {
                hasAnimatedIn = true  // Trigger the animation modifier
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Last 7 days, sparkline")
    }

    private func label(for agg: DailyAggregate, index: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        let dayName = f.string(from: agg.day)
        let kmString = String(format: "%.1f", agg.distance.kilometers)
        let mString = String(format: "%.0f", agg.distance.meters)
        if agg.distance.meters >= 1000 {
            return "\(dayName), \(kmString) kilometers"
        } else {
            return "\(dayName), \(mString) meters"
        }
    }
}

#Preview("Sparkline — typical week") {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let values: [DailyAggregate] = [820, 950, 1_120, 870, 1_400, 760, 1_247].enumerated().map { idx, m in
        DailyAggregate(
            day: cal.date(byAdding: .day, value: -(6 - idx), to: today) ?? today,
            displayUUID: .primary,
            distance: .meters(m)
        )
    }
    return VStack(alignment: .leading, spacing: Space.s2) {
        SparklineView(values: values)
        Text("last 7 days")
            .font(.metaCaption)
            .foregroundStyle(.secondary)
    }
    .padding(Space.s4)
    .frame(width: 320)
    .background(Color.surface)
}

#Preview("Sparkline — empty week") {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let values: [DailyAggregate] = (0..<7).map { idx in
        DailyAggregate(
            day: cal.date(byAdding: .day, value: -(6 - idx), to: today) ?? today,
            displayUUID: .primary,
            distance: .zero
        )
    }
    return SparklineView(values: values)
        .padding(Space.s4)
        .frame(width: 320)
        .background(Color.surface)
}
