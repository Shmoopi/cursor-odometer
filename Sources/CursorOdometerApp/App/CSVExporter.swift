// CSVExporter.swift — turn the current AppStore snapshot into a CSV blob
// suitable for `String.write(to:)`. Keep it dependency-free; no AppKit so
// it can be unit-tested headlessly.

import Foundation
import CursorOdometerCore

enum CSVExporter {
    /// Build a CSV with three sections: today's hourly buckets, the last
    /// 7 days, and per-display totals. Each section is separated by a
    /// blank row. Values are emitted in meters with two decimal places —
    /// the consuming spreadsheet can convert further if it needs to.
    static func makeCSV(
        today: Distance,
        week: [DailyAggregate],
        hourlyToday: [HourlyAggregate],
        perDisplay: [DisplayUUID: Distance],
        displays: [DisplayInfo],
        lifetime: Distance
    ) -> String {
        let isoDate: (Date) -> String = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            return f.string(from: $0)
        }

        var out = "Cursor Odometer export\n"
        out += "exported_at,\(isoDate(Date()))\n"
        out += "lifetime_meters,\(formatMeters(lifetime))\n"
        out += "today_meters,\(formatMeters(today))\n"
        out += "\n"
        out += "section,daily\n"
        out += "day,distance_meters\n"
        for row in week.sorted(by: { $0.day < $1.day }) {
            out += "\(isoDate(row.day)),\(formatMeters(row.distance))\n"
        }
        out += "\n"
        out += "section,hourly_today\n"
        out += "hour,distance_meters\n"
        // Aggregate per hour across displays so each line is one row.
        var hourTotals: [Date: Distance] = [:]
        for row in hourlyToday {
            hourTotals[row.hour, default: .zero] += row.distance
        }
        for hour in hourTotals.keys.sorted() {
            out += "\(isoDate(hour)),\(formatMeters(hourTotals[hour] ?? .zero))\n"
        }
        out += "\n"
        out += "section,per_display_today\n"
        out += "display_uuid,display_name,distance_meters\n"
        let lookup = Dictionary(uniqueKeysWithValues: displays.map { ($0.uuid, $0.displayName) })
        for (uuid, dist) in perDisplay.sorted(by: { $0.value > $1.value }) {
            let name = lookup[uuid] ?? uuid.rawValue
            out += "\(uuid.rawValue),\(escape(name)),\(formatMeters(dist))\n"
        }
        return out
    }

    private static func formatMeters(_ d: Distance) -> String {
        String(format: "%.2f", d.meters)
    }

    private static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
}
