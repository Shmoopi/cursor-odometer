import Foundation
import CoreGraphics

/// One sample from the cursor stream, before distance integration.
public struct CursorEvent: Hashable, Sendable {
    public let location: CGPoint           // global points, BL origin
    public let displayUUID: DisplayUUID?
    public let timestamp: TimeInterval     // monotonic

    public init(
        location: CGPoint,
        displayUUID: DisplayUUID?,
        timestamp: TimeInterval
    ) {
        self.location = location
        self.displayUUID = displayUUID
        self.timestamp = timestamp
    }
}

/// Result of integrating two consecutive samples on the same display.
public struct DistanceDelta: Hashable, Sendable {
    public let distance: Distance
    public let displayUUID: DisplayUUID
    public let timestamp: TimeInterval

    public init(distance: Distance, displayUUID: DisplayUUID, timestamp: TimeInterval) {
        self.distance = distance
        self.displayUUID = displayUUID
        self.timestamp = timestamp
    }
}

/// One row in `motion_segment` — a continuous run of motion
/// with no gap >250 ms.
public struct MotionSegment: Hashable, Sendable {
    public let id: Int64
    public let startTime: Date
    public let endTime: Date
    public let displayUUID: DisplayUUID
    public let distance: Distance

    public init(
        id: Int64,
        startTime: Date,
        endTime: Date,
        displayUUID: DisplayUUID,
        distance: Distance
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.displayUUID = displayUUID
        self.distance = distance
    }
}

/// Hourly rollup row (`hourly_aggregate`).
public struct HourlyAggregate: Hashable, Sendable {
    public let hour: Date           // truncated to hour boundary
    public let displayUUID: DisplayUUID
    public let distance: Distance

    public init(hour: Date, displayUUID: DisplayUUID, distance: Distance) {
        self.hour = hour
        self.displayUUID = displayUUID
        self.distance = distance
    }
}

/// Daily rollup row. Used for week/month/year/all-time queries.
public struct DailyAggregate: Hashable, Sendable {
    public let day: Date            // truncated to day boundary (UTC)
    public let displayUUID: DisplayUUID
    public let distance: Distance

    public init(day: Date, displayUUID: DisplayUUID, distance: Distance) {
        self.day = day
        self.displayUUID = displayUUID
        self.distance = distance
    }
}
