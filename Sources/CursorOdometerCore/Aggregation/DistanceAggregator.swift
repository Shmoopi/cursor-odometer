import Foundation

/// Buffers `DistanceDelta`s into open per-display motion segments and flushes
/// them to the `PersistenceStoreProtocol` at most every 5 seconds (or on
/// `force: true`).
public actor DistanceAggregator {
    private let store: PersistenceStoreProtocol
    private let clock: ClockProtocol
    private let flushInterval: TimeInterval
    private let segmentGap: TimeInterval

    private var openSegments: [DisplayUUID: OpenSegment] = [:]
    private var lastFlush: Date
    private var totalSegments: Int = 0

    public init(
        store: PersistenceStoreProtocol,
        clock: ClockProtocol,
        flushInterval: TimeInterval = 5.0,
        segmentGapSeconds: TimeInterval = 0.250
    ) {
        self.store = store
        self.clock = clock
        self.flushInterval = flushInterval
        self.segmentGap = segmentGapSeconds
        self.lastFlush = clock.now()
    }

    /// Append one delta. May extend the current open motion segment for the
    /// display, or seal it and start a new one if the gap or display changed.
    public func add(_ delta: DistanceDelta) {
        let now = clock.now()
        if var open = openSegments[delta.displayUUID] {
            let gap = now.timeIntervalSince(open.endTime)
            if gap <= segmentGap {
                open.endTime = now
                open.distance += delta.distance
                openSegments[delta.displayUUID] = open
                return
            } else {
                sealAndQueue(open)
            }
        }
        // Open a fresh segment.
        openSegments[delta.displayUUID] = OpenSegment(
            startTime: now,
            endTime: now,
            displayUUID: delta.displayUUID,
            distance: delta.distance
        )
    }

    /// Persist any pending segments. With `force == false` this is a no-op
    /// until `flushInterval` seconds have elapsed since the last flush.
    public func flush(force: Bool) async throws {
        let now = clock.now()
        if !force && now.timeIntervalSince(lastFlush) < flushInterval { return }

        // Seal every open segment for flushing.
        for (_, open) in openSegments { sealAndQueue(open) }
        openSegments.removeAll(keepingCapacity: true)
        let pending = pendingSegments
        pendingSegments.removeAll(keepingCapacity: true)
        if !pending.isEmpty {
            try await store.record(segments: pending)
            totalSegments += pending.count
        }
        lastFlush = now
    }

    /// Total count of motion segments that have been flushed during this
    /// aggregator's lifetime. Used by tests; not part of the wire format.
    public var totalSegmentsFlushed: Int { totalSegments }

    // MARK: - private

    private struct OpenSegment {
        var startTime: Date
        var endTime: Date
        var displayUUID: DisplayUUID
        var distance: Distance
    }

    private var pendingSegments: [MotionSegment] = []

    private func sealAndQueue(_ open: OpenSegment) {
        // Note: id 0 means "let store assign" — InMemoryPersistenceStore honors
        // this; SQLite store auto-increments primary key.
        pendingSegments.append(
            MotionSegment(
                id: 0,
                startTime: open.startTime,
                endTime: open.endTime,
                displayUUID: open.displayUUID,
                distance: open.distance
            )
        )
    }
}
