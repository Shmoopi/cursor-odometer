import Testing
import Foundation
import CoreGraphics
@testable import CursorOdometerCore

@Suite("DistanceAggregator + InMemoryPersistenceStore")
struct AggregationStoreTests {

    // Single sample → daily aggregate equals its distance
    @Test("Single sample → daily aggregate equals its distance")
    func singleSampleDailyAggregate() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)
        let delta = DistanceDelta(distance: .meters(2), displayUUID: .primary, timestamp: 0)
        await aggregator.add(delta)
        try await aggregator.flush(force: true)
        let day = clock.now().truncatedToDayUTC
        let range = day..<day.addingTimeInterval(86_400)
        let buckets = try await store.dailyBreakdown(in: range, display: nil)
        #expect(buckets.count == 1)
        #expect(buckets.first?.distance == .meters(2))
    }

    // Three samples within one day sum
    @Test("Three samples within one day sum to one daily aggregate")
    func threeSamplesSum() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)

        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: .primary, timestamp: 0))
        clock.advance(by: 0.1)
        await aggregator.add(DistanceDelta(distance: .meters(2), displayUUID: .primary, timestamp: 0.1))
        clock.advance(by: 0.1)
        await aggregator.add(DistanceDelta(distance: .meters(3), displayUUID: .primary, timestamp: 0.2))
        try await aggregator.flush(force: true)

        let day = clock.now().truncatedToDayUTC
        let range = day..<day.addingTimeInterval(86_400)
        let buckets = try await store.dailyBreakdown(in: range, display: nil)
        let total = buckets.map(\.distance).reduce(.zero, +)
        #expect(total == .meters(6))
    }

    // 23:59:59 + 00:00:01 → two distinct daily buckets
    @Test("Samples crossing UTC midnight land in two distinct daily buckets")
    func midnightSplits() async throws {
        // 1_700_000_000 = 2023-11-14 22:13:20 UTC. Pick a sample that's seconds before next-day boundary.
        let nearMidnight = Date(timeIntervalSince1970: 1_700_006_399)  // close to 23:59:59
        let clock = FakeClock(nearMidnight)
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)

        // First delta: at 23:59:59 of day X.
        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: .primary, timestamp: 0))
        try await aggregator.flush(force: true)

        clock.advance(by: 2)  // crosses midnight
        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: .primary, timestamp: 2))
        try await aggregator.flush(force: true)

        let dayBefore = nearMidnight.truncatedToDayUTC
        let dayAfter = clock.now().truncatedToDayUTC
        let range = dayBefore..<dayAfter.addingTimeInterval(86_400)
        let buckets = try await store.dailyBreakdown(in: range, display: nil)
        #expect(buckets.count == 2)
    }

    // DST is bucketed in UTC, so DST shifts don't double count
    @Test("DST spring-forward simulation does not double-count or lose samples")
    func dstSpringForward() async throws {
        // Wall clock jumps forward 1 hour; UTC bucketing unaffected.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = FakeClock(start)
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)

        await aggregator.add(DistanceDelta(distance: .meters(5), displayUUID: .primary, timestamp: 0))
        try await aggregator.flush(force: true)

        // DST spring-forward: wall clock jumps by an hour but monotonic doesn't budge.
        clock.setWallClock(start.addingTimeInterval(3_600))
        await aggregator.add(DistanceDelta(distance: .meters(7), displayUUID: .primary, timestamp: 0))
        try await aggregator.flush(force: true)

        let total = await store.lifetimeTotal
        #expect(total == .meters(12))
    }

    @Test("DST fall-back simulation does not double-count or lose samples")
    func dstFallBack() async throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = FakeClock(start.addingTimeInterval(3_600))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)

        await aggregator.add(DistanceDelta(distance: .meters(5), displayUUID: .primary, timestamp: 0))
        try await aggregator.flush(force: true)

        // Wall clock jumps backward by 1 hour. We should still record without
        // duplicating — segments use monotonic deltas, not wall.
        clock.setWallClock(start)
        await aggregator.add(DistanceDelta(distance: .meters(7), displayUUID: .primary, timestamp: 0))
        try await aggregator.flush(force: true)

        let total = await store.lifetimeTotal
        #expect(total == .meters(12))
    }

    // System clock backward; store dedupes by monotonic ID
    @Test("System clock set backward does not produce duplicate aggregates")
    func clockRollbackNoDuplicates() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)

        await aggregator.add(DistanceDelta(distance: .meters(2), displayUUID: .primary, timestamp: 0))
        try await aggregator.flush(force: true)

        clock.setWallClock(Date(timeIntervalSince1970: 1_700_000_000 - 3_600))
        await aggregator.add(DistanceDelta(distance: .meters(3), displayUUID: .primary, timestamp: 1))
        try await aggregator.flush(force: true)

        let total = await store.lifetimeTotal
        #expect(total == .meters(5))   // exactly the sum of unique inputs
    }

    // Querying a date with no samples returns zero
    @Test("Querying empty date returns zero distance")
    func queryEmptyDate() async throws {
        let store = InMemoryPersistenceStore()
        let day = Date(timeIntervalSince1970: 0).truncatedToDayUTC
        let range = day..<day.addingTimeInterval(86_400)
        let total = try await store.distance(in: range, display: nil)
        #expect(total == .zero)
    }

    // resetAll wipes everything atomically
    @Test("resetAll wipes lifetime and aggregates")
    func resetAllWipes() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)
        await aggregator.add(DistanceDelta(distance: .meters(99), displayUUID: .primary, timestamp: 0))
        try await aggregator.flush(force: true)
        #expect(await store.lifetimeTotal == .meters(99))
        try await store.resetAll()
        #expect(await store.lifetimeTotal == .zero)
    }

    // Concurrent appends serialised; final sum correct
    @Test("Concurrent appends from many tasks produce correct total")
    func concurrentAppends() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)

        let count = 200
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask {
                    let d = DistanceDelta(distance: .millimeters(1.5),
                                          displayUUID: .primary,
                                          timestamp: TimeInterval(i) * 0.001)
                    await aggregator.add(d)
                }
            }
        }
        try await aggregator.flush(force: true)

        let total = await store.lifetimeTotal
        #expect(total == .millimeters(Double(count) * 1.5))
    }

    // flushIfNeeded honours the 5s interval rule
    @Test("flushIfNeeded waits for 5s by default; force=true flushes immediately")
    func flushTiming() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)

        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: .primary, timestamp: 0))

        // Without time advancing, non-forced flush is a no-op.
        try await aggregator.flush(force: false)
        #expect(await store.lifetimeTotal == .zero)

        // Advance < 5 s → still no-op.
        clock.advance(by: 4)
        try await aggregator.flush(force: false)
        #expect(await store.lifetimeTotal == .zero)

        // Advance past threshold → flushes.
        clock.advance(by: 1.1)
        try await aggregator.flush(force: false)
        #expect(await store.lifetimeTotal == .meters(1))
    }

    // motion segment 250 ms gap rule
    @Test("Two deltas within 250ms collapse into one motion segment per display")
    func segmentCoalescing() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)

        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: .primary, timestamp: 0))
        clock.advance(by: 0.1)
        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: .primary, timestamp: 0.1))
        clock.advance(by: 0.1)
        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: .primary, timestamp: 0.2))
        try await aggregator.flush(force: true)

        // We expose internal counters for tests via a probe.
        let segCount = await aggregator.totalSegmentsFlushed
        #expect(segCount == 1)
    }

    @Test("Gap > 250ms starts a new motion segment")
    func segmentBreakOnGap() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)

        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: .primary, timestamp: 0))
        clock.advance(by: 0.5)   // gap > 250 ms
        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: .primary, timestamp: 0.5))
        try await aggregator.flush(force: true)

        let segCount = await aggregator.totalSegmentsFlushed
        #expect(segCount == 2)
    }

    @Test("Display change starts a new motion segment")
    func segmentBreakOnDisplayChange() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)

        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: DisplayUUID("a"), timestamp: 0))
        clock.advance(by: 0.05)
        await aggregator.add(DistanceDelta(distance: .meters(1), displayUUID: DisplayUUID("b"), timestamp: 0.05))
        try await aggregator.flush(force: true)

        let segCount = await aggregator.totalSegmentsFlushed
        #expect(segCount == 2)
    }
}
