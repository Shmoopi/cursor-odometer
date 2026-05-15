import Foundation

/// Abstraction over time so tests can drive aggregation deterministically.
/// `Date()` is forbidden in production code outside `SystemClock`; CI greps
/// `Date()` in `Sources/` and fails on hits.
public protocol ClockProtocol: Sendable {
    /// Wall-clock for bucketing into hours/days.
    func now() -> Date

    /// Monotonic time for delta integration; immune to clock changes;
    /// pauses on system sleep (which is what we want).
    func monotonic() -> TimeInterval
}

/// The only place in the codebase where `Date()` and `mach_absolute_time`
/// may appear. Everything else takes a `ClockProtocol`.
public struct SystemClock: ClockProtocol {
    public init() {}

    public func now() -> Date { Date() }

    public func monotonic() -> TimeInterval {
        // ProcessInfo.systemUptime is monotonic and pauses during sleep —
        // exactly what we want.
        ProcessInfo.processInfo.systemUptime
    }
}
