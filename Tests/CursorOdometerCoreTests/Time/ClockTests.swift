import Testing
import Foundation
@testable import CursorOdometerCore

@Suite("FakeClock smoke")
struct ClockTests {
    @Test("FakeClock.now returns the seeded date until advance")
    func nowIsSeeded() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = FakeClock(start)
        #expect(clock.now() == start)
    }

    @Test("FakeClock.advance moves both wall and monotonic clocks")
    func advanceMovesBothClocks() {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000), monotonic: 5)
        clock.advance(by: 7)
        #expect(clock.now() == Date(timeIntervalSince1970: 1_007))
        #expect(clock.monotonic() == 12)
    }

    @Test("FakeClock.setWallClock changes wall time without monotonic")
    func setWallClockIndependentOfMonotonic() {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000), monotonic: 5)
        clock.setWallClock(Date(timeIntervalSince1970: 0))
        #expect(clock.now() == Date(timeIntervalSince1970: 0))
        #expect(clock.monotonic() == 5)
    }

    @Test("FakeClock.schedule fires due work in order on advance")
    func scheduleFiresInOrder() {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let recorded = Recorder<Int>()
        clock.schedule(after: 1) { recorded.append(1) }
        clock.schedule(after: 3) { recorded.append(3) }
        clock.schedule(after: 2) { recorded.append(2) }
        clock.advance(by: 5)
        #expect(recorded.values == [1, 2, 3])
    }
}

/// Tiny thread-safe collector so closures can record values from `FakeClock`.
final class Recorder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [T] = []
    func append(_ value: T) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }
    var values: [T] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}
