// PreviewSupport.swift — UI-only fixtures for SwiftUI `#Preview` blocks.
//
// What lives here:
//   • `PreviewPersistenceStore` — a deliberately dumb actor that returns
//     canned aggregates per `Scenario`. It is *not* a working store — calls
//     to `record(segments:)` only update the lifetime sidecar and otherwise
//     ignore inputs. It exists so previews render plausible numbers without
//     having to seed a real store on every Xcode preview rebuild.
//   • `PreviewDisplayGeometry` — fixed two-display geometry for previews.
//   • `DisplayInfo.previewBuiltin` / `.previewStudio` — geometry fixtures.

import Foundation
import CoreGraphics
import CursorOdometerCore

/// Returns canned aggregates without doing any real bucketing — fast and
/// stable enough for `#Preview` rendering. For tests and the running app
/// use `InMemoryPersistenceStore` from `CursorOdometerCore` instead.
actor PreviewPersistenceStore: PersistenceStoreProtocol {
    private var lifetime: Distance
    private let dailyData: [DailyAggregate]
    private let hourlyData: [HourlyAggregate]
    private let perDisplay: [DisplayUUID: Distance]
    private let todayValue: Distance

    init(scenario: Scenario = .typical) {
        switch scenario {
        case .empty:
            self.lifetime = .zero
            self.dailyData = []
            self.hourlyData = []
            self.perDisplay = [:]
            self.todayValue = .zero
        case .warmingUp:
            self.lifetime = .millimeters(34)
            self.dailyData = []
            self.hourlyData = []
            self.perDisplay = [DisplayUUID.primary: .millimeters(34)]
            self.todayValue = .millimeters(34)
        case .typical:
            self.lifetime = .meters(42_700)
            self.dailyData = PreviewSeed.makeFakeDailies()
            self.hourlyData = PreviewSeed.makeFakeHourly()
            self.perDisplay = [
                DisplayUUID("builtin-retina"): .meters(742),
                DisplayUUID("studio-display"): .meters(505)
            ]
            self.todayValue = .meters(1_247.3)
        }
    }

    func record(segments: [MotionSegment]) async throws {
        for segment in segments {
            lifetime = lifetime + segment.distance
        }
    }

    func distance(in range: Range<Date>, display: DisplayUUID?) async throws -> Distance {
        let now = Date()
        if range.contains(now) {
            return todayValue
        }
        return .zero
    }

    func hourlyBreakdown(in range: Range<Date>, display: DisplayUUID?) async throws -> [HourlyAggregate] {
        hourlyData
    }

    func dailyBreakdown(in range: Range<Date>, display: DisplayUUID?) async throws -> [DailyAggregate] {
        dailyData
    }

    func perDisplayTotals(in range: Range<Date>) async throws -> [DisplayUUID: Distance] {
        perDisplay
    }

    var lifetimeTotal: Distance {
        get async { lifetime }
    }

    func resetAll() async throws {
        lifetime = .zero
    }

    func deleteSegments(in range: Range<Date>) async throws {
        // Preview store: no-op. The `Scenario` snapshot is read-only.
    }

    func checkIntegrity() async throws -> IntegrityCheckOutcome { .ok }

    enum Scenario: Sendable {
        case empty
        case warmingUp
        case typical
    }
}

// MARK: - Seed data (shared between previews and `AppStore.live()`)

/// Reusable canned data for preview scenarios.
enum PreviewSeed {
    /// Seven days of fake daily totals ending today, ascending.
    static func makeFakeDailies() -> [DailyAggregate] {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let days: [Double] = [820, 950, 1_120, 870, 1_400, 760, 1_247]
        return days.enumerated().map { (offset, meters) in
            let day = cal.date(byAdding: .day, value: -(6 - offset), to: today) ?? today
            return DailyAggregate(day: day,
                                  displayUUID: .primary,
                                  distance: .meters(meters))
        }
    }

    /// 24 hourly buckets ending now, with a low-at-night, high-mid-day curve.
    static func makeFakeHourly() -> [HourlyAggregate] {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        return (0..<24).map { h in
            let hour = cal.date(byAdding: .hour, value: -h, to: now) ?? now
            let intensity = max(0, 0.3 + sin(Double(h) * .pi / 12) * 0.7)
            return HourlyAggregate(hour: hour,
                                   displayUUID: .primary,
                                   distance: .meters(intensity * 100))
        }
    }
}

// MARK: - Preview displays

extension DisplayInfo {
    static let previewBuiltin = DisplayInfo(
        uuid: DisplayUUID("builtin-retina"),
        displayName: "Built-in Retina",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        physicalSize: CGSize(width: 286, height: 179),
        backingScaleFactor: 2,
        isPrimary: true
    )

    static let previewStudio = DisplayInfo(
        uuid: DisplayUUID("studio-display"),
        displayName: "Studio Display",
        frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        physicalSize: CGSize(width: 596, height: 336),
        backingScaleFactor: 2,
        isPrimary: false
    )
}

/// Fixed two-display geometry for previews.
final class PreviewDisplayGeometry: DisplayGeometryProviding, @unchecked Sendable {
    let displays: [DisplayInfo] = [.previewBuiltin, .previewStudio]
    func display(at point: CGPoint) -> DisplayInfo? {
        displays.first { $0.frame.contains(point) } ?? displays.first
    }
}

/// Convenience `#Preview` builder: skips the live sampler entirely.
extension AppStore {
    static func preview(scenario: PreviewPersistenceStore.Scenario = .typical) -> AppStore {
        AppStore(persistence: PreviewPersistenceStore(scenario: scenario),
                 geometry: PreviewDisplayGeometry())
    }
}
