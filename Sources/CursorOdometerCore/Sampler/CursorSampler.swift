import Foundation
import CoreGraphics

/// Owns the sampling state machine. Wraps an `EventSource`,
/// applies jitter floor + cross-display teleport guard + shake-to-find filter,
/// emits `DistanceDelta` to the `DistanceAggregator`. Idempotent start/stop.
///
/// **Jitter floor rationale.** Sub-pt cursor motion below human perception
/// (mouse tremor, trackpad palm settle, sub-pixel rounding in the cursor
/// server) integrates into the lifetime total as phantom distance. A 2.0 pt
/// floor ≈ 0.4 mm at typical Retina density — below the smallest single-click
/// movement the OS produces — so the threshold filters noise without losing
/// genuine slow drift, which is recovered by the "don't update baseline on
/// sub-jitter" accumulation rule below.
///
/// **Shake-to-find filter.** macOS amplifies cursor size when the user
/// wiggles the mouse rapidly. The cursor really does travel that screen
/// distance, but it's a UI gesture, not productive motion. We detect bursts
/// of >3 direction reversals in a 400 ms window with cumulative motion
/// >1500 pt and drop those deltas.
public actor CursorSampler {
    private let source: EventSource
    private let geometry: any DisplayGeometryProviding
    private let calculator: DistanceCalculator
    private let aggregator: DistanceAggregator
    private let clock: ClockProtocol
    private let jitterFloorPoints: Double
    private let crossDisplayTeleportThresholdPoints: Double
    private let countCrossDisplayTransitions: Bool
    private let baselineMaxGapSeconds: TimeInterval
    private let shakeDetectionEnabled: Bool
    private let shakeWindowSeconds: TimeInterval
    private let shakeMinReversals: Int
    private let shakeMinCumulativePoints: Double

    private var lastPoint: CGPoint?
    private var lastDisplay: DisplayUUID?
    private var lastTimestamp: TimeInterval?
    private var pumpTask: Task<Void, Never>?
    private var running = false
    private var pendingCount = 0
    private var processedCount = 0

    /// Rolling window of recent motion deltas, used by the shake-to-find
    /// filter. Pruned every ingest tick to `shakeWindowSeconds` of history.
    private var recentMotion: [RecentMotion] = []

    private struct RecentMotion {
        let timestamp: TimeInterval
        let dx: CGFloat
        let dy: CGFloat
        let magnitude: CGFloat
    }

    /// Total events the sampler has fully processed since `start()`.
    /// Used by tests to await a deterministic drain target.
    public var eventsProcessed: Int { processedCount }

    /// `true` between `start()` (after it returns) and `stop()`. Used by the
    /// AppStore watchdog to detect and recover from any drift between
    /// "tracking should be on" UI state and the actual sampler state — e.g.,
    /// if a sleep/wake notification was dropped, the next refresh tick will
    /// restart the sampler.
    public var isRunning: Bool { running }

    public init(
        source: EventSource,
        geometry: any DisplayGeometryProviding,
        calculator: DistanceCalculator,
        aggregator: DistanceAggregator,
        clock: ClockProtocol,
        jitterFloorPoints: Double = 2.0,
        crossDisplayTeleportThresholdPoints: Double = 200,
        countCrossDisplayTransitions: Bool = false,
        baselineMaxGapSeconds: TimeInterval = 30,
        shakeDetectionEnabled: Bool = true,
        shakeWindowSeconds: TimeInterval = 0.4,
        shakeMinReversals: Int = 3,
        shakeMinCumulativePoints: Double = 1500
    ) {
        self.source = source
        self.geometry = geometry
        self.calculator = calculator
        self.aggregator = aggregator
        self.clock = clock
        self.jitterFloorPoints = jitterFloorPoints
        self.crossDisplayTeleportThresholdPoints = crossDisplayTeleportThresholdPoints
        self.countCrossDisplayTransitions = countCrossDisplayTransitions
        self.baselineMaxGapSeconds = baselineMaxGapSeconds
        self.shakeDetectionEnabled = shakeDetectionEnabled
        self.shakeWindowSeconds = shakeWindowSeconds
        self.shakeMinReversals = shakeMinReversals
        self.shakeMinCumulativePoints = shakeMinCumulativePoints
    }

    /// Spin up the underlying source and start consuming its `events` stream.
    /// Idempotent: a second call while already running is a no-op.
    public func start() async {
        guard !running else { return }
        running = true
        await source.start()
        let stream = source.events
        pumpTask = Task { [weak self] in
            for await event in stream {
                await self?.ingest(event: event)
            }
        }
    }

    /// Stop the source, cancel the pump, and clear baseline state. Idempotent.
    public func stop() async {
        guard running else {
            await source.stop()
            return
        }
        running = false
        pumpTask?.cancel()
        pumpTask = nil
        await source.stop()
        lastPoint = nil
        lastDisplay = nil
        lastTimestamp = nil
        recentMotion.removeAll(keepingCapacity: false)
    }

    /// Drop the last-known position. Used on `NSWorkspace.didWakeNotification`
    /// so the first post-wake event yields zero.
    public func resyncBaseline() {
        lastPoint = nil
        lastDisplay = nil
        lastTimestamp = nil
        recentMotion.removeAll(keepingCapacity: true)
    }

    /// Backstop poll path. 4 Hz sweep that compares the last known
    /// position against the system cursor and adds any unaccounted distance.
    public func poll(at point: CGPoint, displayUUID: DisplayUUID?, timestamp: TimeInterval) async {
        let event = CursorEvent(location: point, displayUUID: displayUUID, timestamp: timestamp)
        await ingest(event: event)
    }

    /// Block until every event currently on the queue has been processed.
    /// Test-only convenience; production code should use `flush(force:)`.
    /// Polls until `pendingCount` stays at zero across several consecutive
    /// yields so the pump task has a chance to pull queued stream events.
    /// Heuristic — for high-volume tests prefer `waitForEventsProcessed(_:)`
    /// which is deterministic.
    public func waitForPendingEvents(maxIterations: Int = 4_096) async {
        var stableTicks = 0
        var iterations = 0
        while iterations < maxIterations {
            await Task.yield()
            iterations += 1
            if pendingCount == 0 {
                stableTicks += 1
                // 16 stable ticks ≈ enough headroom for the pump's `for await`
                // to have consumed and dispatched the entire upstream queue.
                if stableTicks >= 16 { return }
            } else {
                stableTicks = 0
            }
        }
    }

    /// Block until `processedCount >= target`. Use this in tests that emit
    /// a known count of events — far more deterministic than the heuristic
    /// `waitForPendingEvents`, which can mis-fire under different actor
    /// schedulers (xcodebuild vs SPM).
    public func waitForEventsProcessed(_ target: Int, maxIterations: Int = 100_000) async {
        var iterations = 0
        while processedCount < target && iterations < maxIterations {
            await Task.yield()
            iterations += 1
        }
    }

    // MARK: - private

    private func ingest(event: CursorEvent) async {
        pendingCount += 1
        defer {
            pendingCount -= 1
            processedCount += 1
        }

        // Off-screen: drop without updating baseline.
        let attributedDisplay = event.displayUUID ?? geometry.display(at: event.location)?.uuid
        guard let displayID = attributedDisplay else {
            // No display attribution: discard, keep baseline so a quick
            // wobble off+back to a real screen doesn't reset the segment.
            return
        }

        // First event ever or post-wake: set baseline only.
        guard let last = lastPoint, let lastDisplayID = lastDisplay,
              let lastTS = lastTimestamp else {
            lastPoint = event.location
            lastDisplay = displayID
            lastTimestamp = event.timestamp
            return
        }

        // Long gap (> 30 s) → reset baseline, no delta.
        let gap = event.timestamp - lastTS
        if gap > baselineMaxGapSeconds {
            lastPoint = event.location
            lastDisplay = displayID
            lastTimestamp = event.timestamp
            return
        }

        // Cross-display teleport guard.
        let raw = last.distance(to: event.location)
        if displayID != lastDisplayID, !countCrossDisplayTransitions,
           raw > CGFloat(crossDisplayTeleportThresholdPoints) {
            lastPoint = event.location
            lastDisplay = displayID
            lastTimestamp = event.timestamp
            return
        }

        // Jitter floor.
        guard Double(raw) > jitterFloorPoints else {
            // Don't update lastPoint: a cluster of sub-jitter moves should
            // accumulate against the original baseline.
            return
        }

        // Shake-to-find filter. Track the motion vector and
        // detect rapid direction reversals; drop the delta while the burst
        // is active but still update baseline so accumulation resumes
        // immediately when the shake settles.
        let dx = event.location.x - last.x
        let dy = event.location.y - last.y
        recentMotion.append(RecentMotion(timestamp: event.timestamp,
                                         dx: dx, dy: dy, magnitude: raw))
        pruneRecentMotion(now: event.timestamp)
        if shakeDetectionEnabled && isShakeBurstActive() {
            lastPoint = event.location
            lastDisplay = displayID
            lastTimestamp = event.timestamp
            return
        }

        let distance = calculator.distance(from: last, to: event.location)
        if distance > .zero {
            await aggregator.add(DistanceDelta(
                distance: distance,
                displayUUID: displayID,
                timestamp: event.timestamp
            ))
        }
        lastPoint = event.location
        lastDisplay = displayID
        lastTimestamp = event.timestamp
    }

    /// Drop motion-history entries older than the shake window so we don't
    /// hold unbounded state. Called on every `ingest()`.
    private func pruneRecentMotion(now: TimeInterval) {
        let cutoff = now - shakeWindowSeconds
        var firstKept = 0
        for entry in recentMotion {
            if entry.timestamp >= cutoff { break }
            firstKept += 1
        }
        if firstKept > 0 {
            recentMotion.removeFirst(firstKept)
        }
    }

    /// `true` when the rolling window shows >`shakeMinReversals` direction
    /// reversals and cumulative motion >`shakeMinCumulativePoints` —
    /// the classic shake-to-find signature.
    private func isShakeBurstActive() -> Bool {
        guard recentMotion.count >= shakeMinReversals + 1 else { return false }
        var reversals = 0
        var cumulative: CGFloat = 0
        var prevSign: Int = 0
        for entry in recentMotion {
            cumulative += entry.magnitude
            // Track sign of dx; for vertical shakes, dy would do — using the
            // dominant axis covers both. Below 0.5pt is treated as no-sign.
            let axis = abs(entry.dx) >= abs(entry.dy) ? entry.dx : entry.dy
            let sign = axis > 0.5 ? 1 : (axis < -0.5 ? -1 : 0)
            if sign != 0 {
                if prevSign != 0 && sign != prevSign { reversals += 1 }
                prevSign = sign
            }
        }
        return reversals >= shakeMinReversals
            && Double(cumulative) >= shakeMinCumulativePoints
    }
}
