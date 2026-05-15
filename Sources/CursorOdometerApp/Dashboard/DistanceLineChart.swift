// DistanceLineChart.swift — Swift Charts smooth line.
// Uses Charts framework for native macOS rendering, monotone interpolation
// for "calm document" visuals, and respects Reduce Motion for chart updates.
//
// Accepts either daily (Week/Month/Year) or hourly (Day/Today) buckets via a
// granularity flag so the same component drives every dashboard range.

import SwiftUI
import Charts
import CursorOdometerCore

/// One sample drawn on the line/area chart. The `date` is the bucket boundary
/// and `value` is the y-axis magnitude in the unit named by `unitLabel`.
struct ChartPoint: Hashable {
    let date: Date
    let value: Double
}

/// Time granularity of the bucketed series. Drives axis stride + chart-mark
/// `unit`, so the line and labels line up with the underlying bucketing.
enum ChartGranularity {
    case hour
    case day

    var calendarUnit: Calendar.Component {
        switch self {
        case .hour: return .hour
        case .day:  return .day
        }
    }
}

struct DistanceLineChart: View {
    let points: [ChartPoint]
    var unitLabel: String = "m"
    var granularity: ChartGranularity = .day

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Chart {
            ForEach(points, id: \.date) { p in
                LineMark(
                    x: .value(xAxisLabel, p.date, unit: granularity.calendarUnit),
                    y: .value(unitLabel, p.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.colorLifetime)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))

                AreaMark(
                    x: .value(xAxisLabel, p.date, unit: granularity.calendarUnit),
                    y: .value(unitLabel, p.value)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.colorLifetime.opacity(0.18), Color.colorLifetime.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .chartXAxis { xAxisContent }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel()
                    .font(.metaCaption)
            }
        }
        .animation(reduceMotion ? nil : .rangeChange, value: points)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityChartDescriptor(self)
    }

    private var xAxisLabel: String {
        switch granularity {
        case .hour: return "Hour"
        case .day:  return "Day"
        }
    }

    private var accessibilityTitle: String {
        switch granularity {
        case .hour: return "Distance over hours of today"
        case .day:  return "Distance over time"
        }
    }

    @AxisContentBuilder
    private var xAxisContent: some AxisContent {
        switch granularity {
        case .hour:
            // 24 hours: show a tick every 3 hours so the axis stays readable
            // at the 600pt-wide dashboard chart.
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine().foregroundStyle(Color.hairline)
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)))
            }
        case .day:
            // Pick a stride that won't overcrowd the axis: a tick per day
            // works for ≤14 days, weekly for ≤90 days, monthly otherwise.
            switch points.count {
            case 0...14:
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            case 15...90:
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            default:
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisGridLine().foregroundStyle(Color.hairline)
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
        }
    }
}

// MARK: - Convenience builders

extension DistanceLineChart {
    /// Build the chart from daily aggregates (Week/Month/Year ranges).
    init(values: [DailyAggregate], unitLabel: String) {
        self.init(
            points: values.map { ChartPoint(date: $0.day, value: $0.distance.meters) },
            unitLabel: unitLabel,
            granularity: .day
        )
    }

    /// Build the chart from hourly aggregates (Today range).
    init(hourlyValues: [HourlyAggregate], unitLabel: String) {
        self.init(
            points: hourlyValues.map { ChartPoint(date: $0.hour, value: $0.distance.meters) },
            unitLabel: unitLabel,
            granularity: .hour
        )
    }
}

extension DistanceLineChart: AXChartDescriptorRepresentable {
    nonisolated func makeChartDescriptor() -> AXChartDescriptor {
        // The chart descriptor is read on a background a11y thread; copy
        // values out of `self` synchronously into local state below.
        // SwiftUI views are value types so this read is safe.
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Time",
            range: 0...Double(max(points.count - 1, 1)),
            gridlinePositions: []
        ) { value in "Bucket \(Int(value) + 1)" }

        let maxY = points.map { $0.value }.max() ?? 1
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Meters",
            range: 0...max(maxY, 1),
            gridlinePositions: []
        ) { value in String(format: "%.0f meters", value) }

        let series = AXDataSeriesDescriptor(
            name: "Distance",
            isContinuous: true,
            dataPoints: points.enumerated().map { idx, p in
                AXDataPoint(x: Double(idx), y: p.value)
            }
        )

        return AXChartDescriptor(
            title: "Distance over time",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}

// MARK: - Previews

#Preview("Distance line chart — daily") {
    let cal = Calendar(identifier: .gregorian)
    let today = cal.startOfDay(for: Date())
    let values: [DailyAggregate] = (0..<14).map { idx in
        let day = cal.date(byAdding: .day, value: -(13 - idx), to: today) ?? today
        let m = 600 + Double(idx % 7) * 180 + sin(Double(idx) * 0.5) * 200
        return DailyAggregate(day: day, displayUUID: .primary, distance: .meters(max(0, m)))
    }
    return DistanceLineChart(values: values, unitLabel: "m")
        .frame(width: 600, height: 240)
        .padding()
        .background(Color.surface)
}

#Preview("Distance line chart — hourly today") {
    let cal = Calendar(identifier: .gregorian)
    let startOfDay = cal.startOfDay(for: Date())
    let nowHour = cal.component(.hour, from: Date())
    let values: [HourlyAggregate] = (0...nowHour).map { h in
        let hour = cal.date(byAdding: .hour, value: h, to: startOfDay) ?? startOfDay
        let intensity = max(0, 0.2 + sin(Double(h) * .pi / 12) * 0.7)
        return HourlyAggregate(hour: hour, displayUUID: .primary,
                               distance: .meters(intensity * 120))
    }
    return DistanceLineChart(hourlyValues: values, unitLabel: "m")
        .frame(width: 600, height: 240)
        .padding()
        .background(Color.surface)
}
