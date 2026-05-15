import Foundation

/// Production-grade in-memory `PersistenceStoreProtocol` used both for tests
/// and SwiftUI `#Preview` blocks. Threadsafe via an actor.
public actor InMemoryPersistenceStore: PersistenceStoreProtocol {
    private var segments: [MotionSegment] = []
    private var lifetime: Distance = .zero
    private var nextSegmentID: Int64 = 1

    public init() {}

    public func record(segments newSegments: [MotionSegment]) async throws {
        for segment in newSegments {
            // Honor caller-provided IDs but keep our generator monotonic
            // so a follow-up insert doesn't collide.
            let assigned = segment.id == 0
                ? MotionSegment(id: nextSegmentID,
                                startTime: segment.startTime,
                                endTime: segment.endTime,
                                displayUUID: segment.displayUUID,
                                distance: segment.distance)
                : segment
            segments.append(assigned)
            if assigned.id >= nextSegmentID {
                nextSegmentID = assigned.id + 1
            }
            lifetime += assigned.distance
        }
    }

    public func distance(in range: Range<Date>, display: DisplayUUID?) async throws -> Distance {
        var total = Distance.zero
        for segment in segments where segment.startTime >= range.lowerBound && segment.startTime < range.upperBound {
            if let display, segment.displayUUID != display { continue }
            total += segment.distance
        }
        return total
    }

    public func hourlyBreakdown(in range: Range<Date>, display: DisplayUUID?) async throws -> [HourlyAggregate] {
        try await aggregate(in: range, display: display, granularity: .hour)
            .map { HourlyAggregate(hour: $0.bucket, displayUUID: $0.display, distance: $0.distance) }
            .sorted { ($0.hour, $0.displayUUID.rawValue) < ($1.hour, $1.displayUUID.rawValue) }
    }

    public func dailyBreakdown(in range: Range<Date>, display: DisplayUUID?) async throws -> [DailyAggregate] {
        try await aggregate(in: range, display: display, granularity: .day)
            .map { DailyAggregate(day: $0.bucket, displayUUID: $0.display, distance: $0.distance) }
            .sorted { ($0.day, $0.displayUUID.rawValue) < ($1.day, $1.displayUUID.rawValue) }
    }

    public func perDisplayTotals(in range: Range<Date>) async throws -> [DisplayUUID: Distance] {
        var totals: [DisplayUUID: Distance] = [:]
        for segment in segments where segment.startTime >= range.lowerBound && segment.startTime < range.upperBound {
            totals[segment.displayUUID, default: .zero] += segment.distance
        }
        return totals
    }

    public var lifetimeTotal: Distance {
        get async { lifetime }
    }

    public func resetAll() async throws {
        segments.removeAll()
        lifetime = .zero
        nextSegmentID = 1
    }

    public func deleteSegments(in range: Range<Date>) async throws {
        var removed = Distance.zero
        segments.removeAll { segment in
            let inRange = segment.startTime >= range.lowerBound && segment.startTime < range.upperBound
            if inRange { removed += segment.distance }
            return inRange
        }
        // Lifetime denormalisation has to drop in lockstep so future reads
        // don't hand back numbers that include the deleted slice.
        let remaining = lifetime.micrometers - removed.micrometers
        lifetime = Distance(micrometers: max(0, remaining))
    }

    public func checkIntegrity() async throws -> IntegrityCheckOutcome {
        .ok
    }

    // MARK: - private aggregation

    private struct Bucket: Hashable {
        let bucket: Date
        let display: DisplayUUID
        var distance: Distance
    }

    private enum Granularity { case hour, day }

    private func aggregate(in range: Range<Date>, display: DisplayUUID?, granularity: Granularity) async throws -> [Bucket] {
        var grouped: [String: Bucket] = [:]
        for segment in segments where segment.startTime >= range.lowerBound && segment.startTime < range.upperBound {
            if let display, segment.displayUUID != display { continue }
            let bucket: Date
            switch granularity {
            case .hour: bucket = segment.startTime.truncatedToHourUTC
            case .day:  bucket = segment.startTime.truncatedToDayUTC
            }
            let key = "\(bucket.timeIntervalSince1970)|\(segment.displayUUID.rawValue)"
            if var existing = grouped[key] {
                existing.distance += segment.distance
                grouped[key] = existing
            } else {
                grouped[key] = Bucket(bucket: bucket, display: segment.displayUUID, distance: segment.distance)
            }
        }
        return Array(grouped.values)
    }
}

/// UTC truncation helpers used by all bucketing code.
extension Date {
    /// This `Date` snapped down to the start of its hour in UTC.
    var truncatedToHourUTC: Date {
        let secondsPerHour: TimeInterval = 3_600
        let interval = timeIntervalSince1970
        let truncated = (interval / secondsPerHour).rounded(.down) * secondsPerHour
        return Date(timeIntervalSince1970: truncated)
    }

    /// This `Date` snapped down to the start of its day in UTC.
    var truncatedToDayUTC: Date {
        let secondsPerDay: TimeInterval = 86_400
        let interval = timeIntervalSince1970
        let truncated = (interval / secondsPerDay).rounded(.down) * secondsPerDay
        return Date(timeIntervalSince1970: truncated)
    }
}
