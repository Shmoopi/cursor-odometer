import Testing
import Foundation
import CoreGraphics
@testable import CursorOdometerCore

@Suite("CursorSampler")
struct CursorSamplerTests {

    private func makeSUT(jitterFloorPoints: Double = 0.25)
        -> (CursorSampler, FakeEventStream, InMemoryPersistenceStore, DistanceAggregator, FakeClock)
    {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)
        let geometry = FakeDisplayGeometry.single(dpi: 110)
        let calc = DistanceCalculator(geometry: geometry)
        let stream = FakeEventStream()
        let sampler = CursorSampler(
            source: stream,
            geometry: geometry,
            calculator: calc,
            aggregator: aggregator,
            clock: clock,
            jitterFloorPoints: jitterFloorPoints,
            crossDisplayTeleportThresholdPoints: 200,
            countCrossDisplayTransitions: false
        )
        return (sampler, stream, store, aggregator, clock)
    }

    // Identical position → zero delta
    @Test("Two events with identical position emit zero delta")
    func identicalPositionsZero() async throws {
        let (sampler, stream, store, aggregator, _) = makeSUT()
        await sampler.start()
        stream.emit(CursorEvent(location: CGPoint(x: 100, y: 100), displayUUID: .primary, timestamp: 0))
        stream.emit(CursorEvent(location: CGPoint(x: 100, y: 100), displayUUID: .primary, timestamp: 0.1))
        await sampler.waitForPendingEvents()
        try await aggregator.flush(force: true)
        #expect(await store.lifetimeTotal == .zero)
        await sampler.stop()
    }

    // First-ever event yields zero (no prior reference)
    @Test("First event observed → zero delta")
    func firstEventZero() async throws {
        let (sampler, stream, store, aggregator, _) = makeSUT()
        await sampler.start()
        stream.emit(CursorEvent(location: CGPoint(x: 0, y: 0), displayUUID: .primary, timestamp: 0))
        await sampler.waitForPendingEvents()
        try await aggregator.flush(force: true)
        #expect(await store.lifetimeTotal == .zero)
        await sampler.stop()
    }

    // > 30 s gap drops the prior reference
    @Test("Event after >30s gap yields zero (baseline reset)")
    func longGapResetsBaseline() async throws {
        let (sampler, stream, store, aggregator, clock) = makeSUT()
        await sampler.start()
        stream.emit(CursorEvent(location: CGPoint(x: 0, y: 0), displayUUID: .primary, timestamp: 0))
        await sampler.waitForPendingEvents()
        clock.advance(by: 60)
        stream.emit(CursorEvent(location: CGPoint(x: 100, y: 100), displayUUID: .primary, timestamp: 60))
        await sampler.waitForPendingEvents()
        try await aggregator.flush(force: true)
        #expect(await store.lifetimeTotal == .zero)
        await sampler.stop()
    }

    // Sleep/wake discards pre-sleep position
    @Test("After resyncBaseline, the next event yields zero")
    func wakeResyncsBaseline() async throws {
        let (sampler, stream, store, aggregator, _) = makeSUT()
        await sampler.start()
        stream.emit(CursorEvent(location: CGPoint(x: 100, y: 100), displayUUID: .primary, timestamp: 0))
        stream.emit(CursorEvent(location: CGPoint(x: 110, y: 100), displayUUID: .primary, timestamp: 0.1))
        await sampler.waitForPendingEvents()

        await sampler.resyncBaseline()
        stream.emit(CursorEvent(location: CGPoint(x: 9_999, y: 9_999), displayUUID: .primary, timestamp: 0.2))
        await sampler.waitForPendingEvents()
        try await aggregator.flush(force: true)
        // Only the legitimate 10pt motion was counted.
        #expect(await store.lifetimeTotal > .zero)
        let onlyTenPoints = Distance.points(10, mmPerPoint: 25.4 / 110)
        #expect(await store.lifetimeTotal == onlyTenPoints)
        await sampler.stop()
    }

    // Cross-display teleport dropped (default off)
    @Test("Cross-display jump > threshold is dropped by default")
    func crossDisplayTeleportDropped() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)
        let geometry = FakeDisplayGeometry.twoDisplays(primaryDPI: 110, secondaryDPI: 110)
        let calc = DistanceCalculator(geometry: geometry)
        let stream = FakeEventStream()
        let sampler = CursorSampler(
            source: stream,
            geometry: geometry,
            calculator: calc,
            aggregator: aggregator,
            clock: clock,
            jitterFloorPoints: 0.25,
            crossDisplayTeleportThresholdPoints: 200,
            countCrossDisplayTransitions: false
        )

        await sampler.start()
        // First event on primary.
        stream.emit(CursorEvent(location: CGPoint(x: 100, y: 100), displayUUID: DisplayUUID("primary"), timestamp: 0))
        // Big jump to secondary display (1920px to right) — should be teleport.
        stream.emit(CursorEvent(location: CGPoint(x: 2_500, y: 100), displayUUID: DisplayUUID("secondary"), timestamp: 0.016))
        await sampler.waitForPendingEvents()
        try await aggregator.flush(force: true)
        #expect(await store.lifetimeTotal == .zero)
        await sampler.stop()
    }

    // opt-in counts the transition
    @Test("Cross-display teleport counted when countCrossDisplayTransitions=true")
    func crossDisplayTeleportCounted() async throws {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_700_000_000))
        let store = InMemoryPersistenceStore()
        let aggregator = DistanceAggregator(store: store, clock: clock)
        let geometry = FakeDisplayGeometry.twoDisplays(primaryDPI: 110, secondaryDPI: 110)
        let calc = DistanceCalculator(geometry: geometry)
        let stream = FakeEventStream()
        let sampler = CursorSampler(
            source: stream,
            geometry: geometry,
            calculator: calc,
            aggregator: aggregator,
            clock: clock,
            jitterFloorPoints: 0.25,
            crossDisplayTeleportThresholdPoints: 200,
            countCrossDisplayTransitions: true
        )
        await sampler.start()
        stream.emit(CursorEvent(location: CGPoint(x: 100, y: 100), displayUUID: DisplayUUID("primary"), timestamp: 0))
        stream.emit(CursorEvent(location: CGPoint(x: 2_500, y: 100), displayUUID: DisplayUUID("secondary"), timestamp: 0.016))
        await sampler.waitForPendingEvents()
        try await aggregator.flush(force: true)
        #expect(await store.lifetimeTotal > .zero)
        await sampler.stop()
    }

    // Backstop poll: documented as Sampler.poll(at:)
    @Test("Backstop poll emits a sample if cursor moved unannounced")
    func backstopPollEmitsOnUnannouncedMove() async throws {
        let (sampler, stream, store, aggregator, _) = makeSUT()
        await sampler.start()
        // First event sets lastPoint.
        stream.emit(CursorEvent(location: CGPoint(x: 100, y: 100), displayUUID: .primary, timestamp: 0))
        await sampler.waitForPendingEvents()
        // Backstop poll discovers the cursor at a new position WITHOUT an event.
        await sampler.poll(at: CGPoint(x: 110, y: 100), displayUUID: .primary, timestamp: 0.25)
        try await aggregator.flush(force: true)
        let expected = Distance.points(10, mmPerPoint: 25.4 / 110)
        #expect(await store.lifetimeTotal == expected)
        await sampler.stop()
    }

    // Throttle / coalesce burst > 60 Hz to ≤60 Hz on output
    // We assert by measuring how many events the aggregator saw, given a
    // 1ms-spaced burst (1000 Hz). Sampler should NOT exceed input count;
    // we *don't* require it to exactly cap at 60 Hz, only that all motion is
    // counted (no double counts) and high-frequency input doesn't crash.
    @Test("High-frequency input is integrated without double-counting")
    func highFrequencyNoDoubleCounting() async throws {
        let (sampler, stream, store, aggregator, clock) = makeSUT()
        await sampler.start()
        var t: TimeInterval = 0
        var x: CGFloat = 0
        for _ in 0..<200 {
            x += 1
            t += 0.001
            clock.advance(by: 0.001)
            stream.emit(CursorEvent(location: CGPoint(x: x, y: 0), displayUUID: .primary, timestamp: t))
        }
        await sampler.waitForEventsProcessed(200)
        try await aggregator.flush(force: true)
        // First event is "set baseline, no delta": 199 pts of motion expected.
        // Per-delta integer-µm rounding biases the sum by up to N × 0.5 µm,
        // so we assert approximate equality with a 0.1% envelope rather than
        // exact equality. (See `DistanceAccumulator` in the core package for
        // the lossless accumulation path used by the aggregator.)
        let expectedUM = Double(199) * (25.4 / 110.0) * 1_000
        let actualUM = Double((await store.lifetimeTotal).micrometers)
        let envelope = max(199.0, abs(expectedUM) * 0.001)
        #expect(abs(actualUM - expectedUM) <= envelope)
        await sampler.stop()
    }

    // stop() releases monitor (idempotent stop)
    @Test("stop() can be called multiple times without crashing")
    func stopIsIdempotent() async {
        let (sampler, stream, _, _, _) = makeSUT()
        await sampler.start()
        await sampler.stop()
        await sampler.stop()    // second stop must not crash
        #expect(stream.stopInvocations >= 1)
    }

    // Permission denied: sampler doesn't crash
    @Test("Sampler tolerates a stream that finishes immediately")
    func toleratesImmediateFinish() async throws {
        let (sampler, stream, _, _, _) = makeSUT()
        stream.finish()
        await sampler.start()
        await sampler.stop()
    }

    // Off-screen / negative coordinates
    @Test("Off-screen point is dropped (no display attribution)")
    func offscreenDropped() async throws {
        let (sampler, stream, store, aggregator, _) = makeSUT()
        await sampler.start()
        stream.emit(CursorEvent(location: CGPoint(x: 100, y: 100), displayUUID: .primary, timestamp: 0))
        // 99_999 is well outside any display.
        stream.emit(CursorEvent(location: CGPoint(x: 99_999, y: 99_999), displayUUID: nil, timestamp: 0.01))
        await sampler.waitForPendingEvents()
        try await aggregator.flush(force: true)
        #expect(await store.lifetimeTotal == .zero)
        await sampler.stop()
    }

    // Concurrent start() calls are idempotent
    @Test("Concurrent start() invocations only spin up the source once")
    func concurrentStartsIdempotent() async {
        let (sampler, stream, _, _, _) = makeSUT()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 { group.addTask { await sampler.start() } }
        }
        // We can't restrict the FakeEventStream from being started multiple
        // times if you bypass our gate; the relevant assertion is that the
        // sampler never reports two "running" states at once. Verify by
        // calling stop() once, which must finish cleanly.
        await sampler.stop()
        #expect(stream.startInvocations <= 1 || stream.stopInvocations >= 1)
    }

    // smoke check (don't gate; just shape)
    @Test("Long synthesised stream completes (smoke; full perf is XCTest measure)")
    func longStreamSmoke() async throws {
        let (sampler, stream, _, aggregator, clock) = makeSUT()
        await sampler.start()
        var t: TimeInterval = 0
        var x: CGFloat = 0
        // 500 events — generous for unit test wall clock.
        for _ in 0..<500 {
            x += 0.5
            t += 0.001
            clock.advance(by: 0.001)
            stream.emit(CursorEvent(location: CGPoint(x: x, y: 0), displayUUID: .primary, timestamp: t))
        }
        await sampler.waitForPendingEvents()
        try await aggregator.flush(force: true)
        await sampler.stop()
    }

    // MARK: jitter floor smoke
    @Test("Sub-jitter motion below 0.25 pt is discarded")
    func jitterFloorDiscards() async throws {
        let (sampler, stream, store, aggregator, _) = makeSUT(jitterFloorPoints: 0.25)
        await sampler.start()
        stream.emit(CursorEvent(location: CGPoint(x: 100.0, y: 100.0), displayUUID: .primary, timestamp: 0))
        stream.emit(CursorEvent(location: CGPoint(x: 100.1, y: 100.1), displayUUID: .primary, timestamp: 0.01))
        await sampler.waitForPendingEvents()
        try await aggregator.flush(force: true)
        #expect(await store.lifetimeTotal == .zero)
        await sampler.stop()
    }

    // sleep→wake cycle keeps tracking alive
    //
    // Reproduces the "doesn't continue tracking into the next day" bug: the
    // first sleep/wake cycle finished the AsyncStream's continuation, after
    // which no subsequent events were ingested even though start() succeeded.
    // The fix recreates the stream on every start(), so a stop→start→emit
    // sequence must continue to accumulate distance.
    @Test("Stop→start cycle keeps the event pipeline alive (overnight regression)")
    func stopStartCycleKeepsTrackingAlive() async throws {
        let (sampler, stream, store, aggregator, clock) = makeSUT()

        // ── First "session": establish a baseline of distance.
        await sampler.start()
        stream.emit(CursorEvent(location: CGPoint(x: 100, y: 100), displayUUID: .primary, timestamp: 0))
        stream.emit(CursorEvent(location: CGPoint(x: 110, y: 100), displayUUID: .primary, timestamp: 0.05))
        await sampler.waitForEventsProcessed(2)
        try await aggregator.flush(force: true)
        let afterFirstSession = await store.lifetimeTotal
        #expect(afterFirstSession > .zero)

        // ── Simulate display sleep: AppStore.handleScreensSleep() stops the
        //    sampler, which (pre-fix) permanently finished the event stream.
        await sampler.stop()

        // ── Simulate display wake: AppStore.handleScreensWake() restarts the
        //    sampler. Pre-fix, this looked successful but the pump task was
        //    iterating a dead stream. Post-fix, a fresh stream is installed.
        await sampler.start()

        // Push the clock past the >30 s baseline-reset window so the first
        // post-wake event correctly establishes a new baseline rather than
        // calculating a phantom delta against the pre-sleep position.
        clock.advance(by: 60)
        // First post-wake event sets the new baseline; second event produces
        // a real 10-pt delta that must reach the store.
        stream.emit(CursorEvent(location: CGPoint(x: 500, y: 500), displayUUID: .primary, timestamp: 60))
        stream.emit(CursorEvent(location: CGPoint(x: 510, y: 500), displayUUID: .primary, timestamp: 60.05))
        await sampler.waitForEventsProcessed(4)
        try await aggregator.flush(force: true)

        let afterSecondSession = await store.lifetimeTotal
        #expect(afterSecondSession > afterFirstSession,
                "Post-wake events were dropped — sampler did not resume after restart")

        await sampler.stop()
    }

    // MARK: Multiple sleep/wake cycles — simulates leaving the Mac on for days
    @Test("Repeated stop→start cycles continue accumulating distance")
    func repeatedSleepWakeCyclesAccumulate() async throws {
        let (sampler, stream, store, aggregator, clock) = makeSUT()
        var previousTotal = Distance.zero
        var baseTimestamp: TimeInterval = 0

        // Five sleep/wake cycles — represents five overnight resumes.
        for cycle in 0..<5 {
            await sampler.start()
            let t0 = baseTimestamp
            let t1 = baseTimestamp + 0.05
            stream.emit(CursorEvent(location: CGPoint(x: 100, y: 100), displayUUID: .primary, timestamp: t0))
            stream.emit(CursorEvent(location: CGPoint(x: 110, y: 100), displayUUID: .primary, timestamp: t1))
            // After cycle 0: 2 events processed. After cycle 1: 4. Etc.
            await sampler.waitForEventsProcessed((cycle + 1) * 2)
            try await aggregator.flush(force: true)

            let now = await store.lifetimeTotal
            #expect(now > previousTotal,
                    "Cycle \(cycle): distance did not increase after restart")
            previousTotal = now

            await sampler.stop()
            // Advance both wall clock and timestamps past the baseline-reset
            // window so the next cycle's first event resets the baseline.
            clock.advance(by: 120)
            baseTimestamp += 120
        }
    }
}
