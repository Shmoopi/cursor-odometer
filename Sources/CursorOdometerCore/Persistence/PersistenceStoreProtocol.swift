import Foundation

/// The only module that touches the database.
/// Implemented by the SQLite-backed `SQLitePersistenceStore` and the
/// `InMemoryPersistenceStore` used in tests.
public protocol PersistenceStoreProtocol: Sendable {
    /// Append one batch of motion segments and roll up the corresponding
    /// hourly + daily + lifetime totals atomically.
    func record(segments: [MotionSegment]) async throws

    /// Distance summed across the half-open range `[start, end)`, optionally
    /// filtered by display. Used by view-models to render hero numbers.
    func distance(in range: Range<Date>, display: DisplayUUID?) async throws -> Distance

    /// Hourly buckets in the half-open range, optionally per display.
    /// Returns rows in ascending hour order.
    func hourlyBreakdown(in range: Range<Date>, display: DisplayUUID?) async throws -> [HourlyAggregate]

    /// Daily buckets in the half-open range, optionally per display.
    func dailyBreakdown(in range: Range<Date>, display: DisplayUUID?) async throws -> [DailyAggregate]

    /// Per-display total for the half-open range.
    func perDisplayTotals(in range: Range<Date>) async throws -> [DisplayUUID: Distance]

    /// O(1) read of the lifetime total — denormalised.
    var lifetimeTotal: Distance { get async }

    /// "Reset all data". Wipes all tables.
    func resetAll() async throws

    /// Delete segments whose `startTime` falls inside the half-open range.
    /// Used by "Reset Today" quick action.
    func deleteSegments(in range: Range<Date>) async throws

    /// Run startup integrity check (`PRAGMA integrity_check`).
    /// Returns the recovery action that was taken, if any.
    func checkIntegrity() async throws -> IntegrityCheckOutcome
}

public enum IntegrityCheckOutcome: Sendable, Equatable {
    case ok
    case quarantinedAndRecreated(quarantineURL: URL)
}

public enum PersistenceError: Error, Sendable, Equatable {
    case migrationFailed(String)
    case corrupted
    case diskFull
    case databaseLocked
    case other(String)
}
