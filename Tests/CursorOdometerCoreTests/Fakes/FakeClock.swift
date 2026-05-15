import Foundation
@testable import CursorOdometerCore

/// Controllable `ClockProtocol` for deterministic time-travel in tests.
/// No `Date()`, no real timers anywhere in tests.
public final class FakeClock: ClockProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var nowValue: Date
    private var monotonicValue: TimeInterval
    private var pending: [(Date, @Sendable () -> Void)] = []

    public init(_ start: Date = Date(timeIntervalSince1970: 0), monotonic: TimeInterval = 0) {
        self.nowValue = start
        self.monotonicValue = monotonic
    }

    public func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        return nowValue
    }

    public func monotonic() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return monotonicValue
    }

    /// Advance both wall and monotonic clocks by `interval` seconds, firing
    /// any due scheduled work in order.
    public func advance(by interval: TimeInterval) {
        lock.lock()
        nowValue = nowValue.addingTimeInterval(interval)
        monotonicValue += interval
        let due = pending
            .filter { $0.0 <= nowValue }
            .sorted { $0.0 < $1.0 }
        pending.removeAll { $0.0 <= nowValue }
        lock.unlock()
        for item in due { item.1() }
    }

    /// Move the wall clock independently of the monotonic clock, simulating
    /// a user clock change. Store dedupes by monotonic ID.
    public func setWallClock(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        nowValue = date
    }

    /// Schedule work to fire after `interval` seconds when `advance(by:)`
    /// reaches that point. Used by tests that simulate timers.
    public func schedule(after interval: TimeInterval, _ work: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        pending.append((nowValue.addingTimeInterval(interval), work))
    }
}
