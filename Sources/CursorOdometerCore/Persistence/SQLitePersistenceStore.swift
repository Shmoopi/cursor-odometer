import Foundation
import SQLite3

/// SQLite-backed `PersistenceStoreProtocol`.
/// One serial write queue (the `actor` itself), per-table upserts, integrity
/// check on open with quarantine-and-recreate.
public actor SQLitePersistenceStore: PersistenceStoreProtocol {
    /// Connection lifetime is owned by a class so the actor's nonisolated
    /// `deinit` can free the handle via `sqlite3_close_v2` without re-entering
    /// the actor's isolation domain.
    ///
    /// `@unchecked Sendable` justification: the `var raw: OpaquePointer?` is
    /// only mutated from inside `SQLitePersistenceStore`'s actor-isolated
    /// methods, so reads/writes are already serialised. `sqlite3_close_v2`
    /// is itself safe to call from the deinit thread because the database
    /// is opened with `SQLITE_OPEN_FULLMUTEX`.
    private final class Handle: @unchecked Sendable {
        var raw: OpaquePointer?
        init(raw: OpaquePointer?) { self.raw = raw }
        deinit { if let raw { sqlite3_close_v2(raw) } }
    }

    private var handle: Handle
    private var db: OpaquePointer? {
        get { handle.raw }
        set { handle.raw = newValue }
    }
    private let path: String
    private let pathURL: URL?
    private let isInMemory: Bool
    private let clock: any ClockProtocol

    /// Schema version baked into the binary. Bumped when migrations run.
    private static let schemaVersion: Int32 = 1

    public init(url: URL, clock: any ClockProtocol = SystemClock()) throws {
        self.pathURL = url
        self.path = url.path
        self.isInMemory = false
        self.clock = clock
        let opened = try Self.openAndMigrate(path: url.path, isInMemory: false)
        self.handle = Handle(raw: opened)
    }

    /// In-memory variant for tests / previews.
    public static func inMemory(clock: any ClockProtocol = SystemClock()) throws -> SQLitePersistenceStore {
        try SQLitePersistenceStore(memoryPath: ":memory:", clock: clock)
    }

    private init(memoryPath: String, clock: any ClockProtocol = SystemClock()) throws {
        self.pathURL = nil
        self.path = memoryPath
        self.isInMemory = true
        self.clock = clock
        let opened = try Self.openAndMigrate(path: memoryPath, isInMemory: true)
        self.handle = Handle(raw: opened)
    }

    // MARK: - PersistenceStoreProtocol

    public func record(segments: [MotionSegment]) async throws {
        guard !segments.isEmpty else { return }
        try transaction { db in
            var insert: OpaquePointer?
            try Self.prepare(db: db, sql: """
                INSERT INTO motion_segment (start_time, end_time, display_uuid, distance_um)
                VALUES (?, ?, ?, ?);
                """, into: &insert)
            defer { sqlite3_finalize(insert) }

            for segment in segments {
                sqlite3_reset(insert)
                sqlite3_clear_bindings(insert)
                sqlite3_bind_int64(insert, 1, Int64(segment.startTime.timeIntervalSince1970))
                sqlite3_bind_int64(insert, 2, Int64(segment.endTime.timeIntervalSince1970))
                _ = segment.displayUUID.rawValue.withCString { cstr in
                    sqlite3_bind_text(insert, 3, cstr, -1, Self.transient)
                }
                sqlite3_bind_int64(insert, 4, segment.distance.micrometers)
                guard sqlite3_step(insert) == SQLITE_DONE else {
                    throw PersistenceError.other(Self.lastError(db: db))
                }
            }

            // Hourly + daily upserts and lifetime delta.
            try upsertAggregates(db: db, segments: segments)
            try bumpLifetime(db: db, by: segments.map(\.distance).reduce(.zero, +))
        }
    }

    public func distance(in range: Range<Date>, display: DisplayUUID?) async throws -> Distance {
        let lo = Int64(range.lowerBound.timeIntervalSince1970)
        let hi = Int64(range.upperBound.timeIntervalSince1970)
        var sql = """
            SELECT COALESCE(SUM(distance_um), 0) FROM motion_segment
            WHERE start_time >= ? AND start_time < ?
            """
        if display != nil { sql += " AND display_uuid = ?" }
        var stmt: OpaquePointer?
        try Self.prepare(db: db, sql: sql, into: &stmt)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, lo)
        sqlite3_bind_int64(stmt, 2, hi)
        if let display {
            _ = display.rawValue.withCString { cstr in
                sqlite3_bind_text(stmt, 3, cstr, -1, Self.transient)
            }
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            let total = sqlite3_column_int64(stmt, 0)
            return Distance(micrometers: total)
        }
        return .zero
    }

    public func hourlyBreakdown(in range: Range<Date>, display: DisplayUUID?) async throws -> [HourlyAggregate] {
        let lo = Int64(range.lowerBound.timeIntervalSince1970)
        let hi = Int64(range.upperBound.timeIntervalSince1970)
        var sql = """
            SELECT hour_epoch, display_uuid, distance_um FROM hourly_aggregate
            WHERE hour_epoch >= ? AND hour_epoch < ?
            """
        if display != nil { sql += " AND display_uuid = ?" }
        sql += " ORDER BY hour_epoch ASC, display_uuid ASC"

        var stmt: OpaquePointer?
        try Self.prepare(db: db, sql: sql, into: &stmt)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, lo)
        sqlite3_bind_int64(stmt, 2, hi)
        if let display {
            _ = display.rawValue.withCString { cstr in
                sqlite3_bind_text(stmt, 3, cstr, -1, Self.transient)
            }
        }

        var out: [HourlyAggregate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let hourEpoch = sqlite3_column_int64(stmt, 0)
            let raw = sqlite3_column_text(stmt, 1)
            let uuid = raw.flatMap { String(cString: $0) } ?? ""
            let dist = sqlite3_column_int64(stmt, 2)
            out.append(HourlyAggregate(
                hour: Date(timeIntervalSince1970: TimeInterval(hourEpoch)),
                displayUUID: DisplayUUID(uuid),
                distance: Distance(micrometers: dist)
            ))
        }
        return out
    }

    public func dailyBreakdown(in range: Range<Date>, display: DisplayUUID?) async throws -> [DailyAggregate] {
        let lo = Int64(range.lowerBound.timeIntervalSince1970)
        let hi = Int64(range.upperBound.timeIntervalSince1970)
        var sql = """
            SELECT day_epoch, display_uuid, distance_um FROM daily_aggregate
            WHERE day_epoch >= ? AND day_epoch < ?
            """
        if display != nil { sql += " AND display_uuid = ?" }
        sql += " ORDER BY day_epoch ASC, display_uuid ASC"

        var stmt: OpaquePointer?
        try Self.prepare(db: db, sql: sql, into: &stmt)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, lo)
        sqlite3_bind_int64(stmt, 2, hi)
        if let display {
            _ = display.rawValue.withCString { cstr in
                sqlite3_bind_text(stmt, 3, cstr, -1, Self.transient)
            }
        }

        var out: [DailyAggregate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let dayEpoch = sqlite3_column_int64(stmt, 0)
            let raw = sqlite3_column_text(stmt, 1)
            let uuid = raw.flatMap { String(cString: $0) } ?? ""
            let dist = sqlite3_column_int64(stmt, 2)
            out.append(DailyAggregate(
                day: Date(timeIntervalSince1970: TimeInterval(dayEpoch)),
                displayUUID: DisplayUUID(uuid),
                distance: Distance(micrometers: dist)
            ))
        }
        return out
    }

    public func perDisplayTotals(in range: Range<Date>) async throws -> [DisplayUUID: Distance] {
        let lo = Int64(range.lowerBound.timeIntervalSince1970)
        let hi = Int64(range.upperBound.timeIntervalSince1970)
        let sql = """
            SELECT display_uuid, COALESCE(SUM(distance_um), 0) FROM motion_segment
            WHERE start_time >= ? AND start_time < ?
            GROUP BY display_uuid
            """
        var stmt: OpaquePointer?
        try Self.prepare(db: db, sql: sql, into: &stmt)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, lo)
        sqlite3_bind_int64(stmt, 2, hi)

        var out: [DisplayUUID: Distance] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let raw = sqlite3_column_text(stmt, 0)
            let uuid = raw.flatMap { String(cString: $0) } ?? ""
            let total = sqlite3_column_int64(stmt, 1)
            out[DisplayUUID(uuid)] = Distance(micrometers: total)
        }
        return out
    }

    public var lifetimeTotal: Distance {
        get async {
            var stmt: OpaquePointer?
            do {
                try Self.prepare(db: db, sql: "SELECT distance_um FROM lifetime_total WHERE id = 1;", into: &stmt)
            } catch {
                return .zero
            }
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                return Distance(micrometers: sqlite3_column_int64(stmt, 0))
            }
            return .zero
        }
    }

    public func resetAll() async throws {
        try transaction { db in
            try Self.exec(db: db, sql: """
                DELETE FROM motion_segment;
                DELETE FROM hourly_aggregate;
                DELETE FROM daily_aggregate;
                UPDATE lifetime_total SET distance_um = 0, updated_at = strftime('%s','now') WHERE id = 1;
                """)
        }
    }

    public func deleteSegments(in range: Range<Date>) async throws {
        let lo = Int64(range.lowerBound.timeIntervalSince1970)
        let hi = Int64(range.upperBound.timeIntervalSince1970)
        try transaction { db in
            // Sum what we're about to delete so the lifetime denormalisation
            // can be reduced atomically. SUM is wrapped in COALESCE so an
            // empty range still returns 0 rather than NULL.
            var sumStmt: OpaquePointer?
            try Self.prepare(db: db, sql: """
                SELECT COALESCE(SUM(distance_um), 0) FROM motion_segment
                WHERE start_time >= ? AND start_time < ?;
                """, into: &sumStmt)
            sqlite3_bind_int64(sumStmt, 1, lo)
            sqlite3_bind_int64(sumStmt, 2, hi)
            var removedUM: Int64 = 0
            if sqlite3_step(sumStmt) == SQLITE_ROW {
                removedUM = sqlite3_column_int64(sumStmt, 0)
            }
            sqlite3_finalize(sumStmt)

            // Drop matching segments.
            var delStmt: OpaquePointer?
            try Self.prepare(db: db, sql: """
                DELETE FROM motion_segment WHERE start_time >= ? AND start_time < ?;
                """, into: &delStmt)
            sqlite3_bind_int64(delStmt, 1, lo)
            sqlite3_bind_int64(delStmt, 2, hi)
            guard sqlite3_step(delStmt) == SQLITE_DONE else {
                sqlite3_finalize(delStmt)
                throw PersistenceError.other(Self.lastError(db: db))
            }
            sqlite3_finalize(delStmt)

            // Aggregates are bucketed on UTC boundaries; the local-time range
            // we received doesn't necessarily align to those buckets, so the
            // safest correction is a full rebuild from the surviving
            // motion_segment rows. This is O(N) over lifetime segments — fine
            // for an explicit user-initiated reset.
            try Self.exec(db: db, sql: """
                DELETE FROM hourly_aggregate;
                DELETE FROM daily_aggregate;
                INSERT INTO hourly_aggregate (hour_epoch, display_uuid, distance_um)
                SELECT (start_time / 3600) * 3600,
                       display_uuid,
                       SUM(distance_um)
                FROM motion_segment
                GROUP BY (start_time / 3600) * 3600, display_uuid;
                INSERT INTO daily_aggregate (day_epoch, display_uuid, distance_um)
                SELECT (start_time / 86400) * 86400,
                       display_uuid,
                       SUM(distance_um)
                FROM motion_segment
                GROUP BY (start_time / 86400) * 86400, display_uuid;
                """)

            // Reduce lifetime denormalisation by exactly what we removed.
            var lifeStmt: OpaquePointer?
            try Self.prepare(db: db, sql: """
                UPDATE lifetime_total
                SET distance_um = MAX(0, distance_um - ?), updated_at = strftime('%s','now')
                WHERE id = 1;
                """, into: &lifeStmt)
            sqlite3_bind_int64(lifeStmt, 1, removedUM)
            guard sqlite3_step(lifeStmt) == SQLITE_DONE else {
                sqlite3_finalize(lifeStmt)
                throw PersistenceError.other(Self.lastError(db: db))
            }
            sqlite3_finalize(lifeStmt)
        }
    }

    public func checkIntegrity() async throws -> IntegrityCheckOutcome {
        var stmt: OpaquePointer?
        try Self.prepare(db: db, sql: "PRAGMA integrity_check;", into: &stmt)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw PersistenceError.corrupted
        }
        let raw = sqlite3_column_text(stmt, 0)
        let result = raw.flatMap { String(cString: $0) } ?? ""
        if result == "ok" { return .ok }

        // Quarantine + recreate (only meaningful on a real on-disk database).
        guard let url = pathURL else {
            throw PersistenceError.corrupted
        }
        sqlite3_close_v2(db)
        db = nil
        let timestamp = Int(clock.now().timeIntervalSince1970)
        let quarantine = url.deletingLastPathComponent()
            .appendingPathComponent("corrupt-\(timestamp).sqlite")
        try? FileManager.default.moveItem(at: url, to: quarantine)
        try reopen()
        return .quarantinedAndRecreated(quarantineURL: quarantine)
    }

    // MARK: - private helpers

    private static let transient = unsafeBitCast(OpaquePointer(bitPattern: -1)!, to: sqlite3_destructor_type.self)

    /// Opens (or creates) the SQLite file at `path`, applies WAL/journal pragmas
    /// for on-disk databases, runs all schema migrations, and returns the open
    /// connection pointer. Synchronous so the actor's `init` can call it
    /// without crossing the actor boundary.
    private static func openAndMigrate(path: String, isInMemory: Bool) throws -> OpaquePointer? {
        var pdb: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &pdb, flags, nil) != SQLITE_OK {
            let msg = pdb.map { String(cString: sqlite3_errmsg($0)!) } ?? "open failed"
            sqlite3_close_v2(pdb)
            throw PersistenceError.other(msg)
        }
        if !isInMemory {
            try exec(db: pdb, sql: "PRAGMA journal_mode = WAL;")
            try exec(db: pdb, sql: "PRAGMA synchronous = NORMAL;")
        }
        try exec(db: pdb, sql: "PRAGMA foreign_keys = ON;")
        try migrate(db: pdb)
        return pdb
    }

    private func reopen() throws {
        let opened = try Self.openAndMigrate(path: path, isInMemory: isInMemory)
        self.db = opened
    }

    private static func migrate(db: OpaquePointer?) throws {
        try exec(db: db, sql: """
            CREATE TABLE IF NOT EXISTS motion_segment (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                start_time    INTEGER NOT NULL,
                end_time      INTEGER NOT NULL,
                display_uuid  TEXT    NOT NULL,
                distance_um   INTEGER NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_segment_start ON motion_segment(start_time);

            CREATE TABLE IF NOT EXISTS hourly_aggregate (
                hour_epoch    INTEGER NOT NULL,
                display_uuid  TEXT    NOT NULL,
                distance_um   INTEGER NOT NULL,
                PRIMARY KEY (hour_epoch, display_uuid)
            );

            CREATE TABLE IF NOT EXISTS daily_aggregate (
                day_epoch     INTEGER NOT NULL,
                display_uuid  TEXT    NOT NULL,
                distance_um   INTEGER NOT NULL,
                PRIMARY KEY (day_epoch, display_uuid)
            );

            CREATE TABLE IF NOT EXISTS lifetime_total (
                id          INTEGER PRIMARY KEY CHECK (id = 1),
                distance_um INTEGER NOT NULL,
                updated_at  INTEGER NOT NULL
            );

            INSERT OR IGNORE INTO lifetime_total (id, distance_um, updated_at)
                VALUES (1, 0, strftime('%s','now'));
            """)
        try exec(db: db, sql: "PRAGMA user_version = \(SQLitePersistenceStore.schemaVersion);")
    }

    private func transaction(_ work: (OpaquePointer?) throws -> Void) throws {
        try Self.exec(db: db, sql: "BEGIN IMMEDIATE TRANSACTION;")
        do {
            try work(db)
            try Self.exec(db: db, sql: "COMMIT;")
        } catch {
            _ = try? Self.exec(db: db, sql: "ROLLBACK;")
            throw error
        }
    }

    private func upsertAggregates(db: OpaquePointer?, segments: [MotionSegment]) throws {
        var hourly: [String: (Date, DisplayUUID, Distance)] = [:]
        var daily: [String: (Date, DisplayUUID, Distance)] = [:]
        for seg in segments {
            let h = seg.startTime.truncatedToHourUTC
            let d = seg.startTime.truncatedToDayUTC
            let hKey = "\(h.timeIntervalSince1970)|\(seg.displayUUID.rawValue)"
            let dKey = "\(d.timeIntervalSince1970)|\(seg.displayUUID.rawValue)"
            hourly[hKey, default: (h, seg.displayUUID, .zero)].2 += seg.distance
            daily[dKey, default: (d, seg.displayUUID, .zero)].2 += seg.distance
        }

        var hStmt: OpaquePointer?
        try Self.prepare(db: db, sql: """
            INSERT INTO hourly_aggregate (hour_epoch, display_uuid, distance_um)
            VALUES (?, ?, ?)
            ON CONFLICT(hour_epoch, display_uuid)
            DO UPDATE SET distance_um = distance_um + excluded.distance_um;
            """, into: &hStmt)
        defer { sqlite3_finalize(hStmt) }

        for (_, value) in hourly {
            sqlite3_reset(hStmt)
            sqlite3_clear_bindings(hStmt)
            sqlite3_bind_int64(hStmt, 1, Int64(value.0.timeIntervalSince1970))
            _ = value.1.rawValue.withCString { cstr in
                sqlite3_bind_text(hStmt, 2, cstr, -1, Self.transient)
            }
            sqlite3_bind_int64(hStmt, 3, value.2.micrometers)
            guard sqlite3_step(hStmt) == SQLITE_DONE else {
                throw PersistenceError.other(Self.lastError(db: db))
            }
        }

        var dStmt: OpaquePointer?
        try Self.prepare(db: db, sql: """
            INSERT INTO daily_aggregate (day_epoch, display_uuid, distance_um)
            VALUES (?, ?, ?)
            ON CONFLICT(day_epoch, display_uuid)
            DO UPDATE SET distance_um = distance_um + excluded.distance_um;
            """, into: &dStmt)
        defer { sqlite3_finalize(dStmt) }

        for (_, value) in daily {
            sqlite3_reset(dStmt)
            sqlite3_clear_bindings(dStmt)
            sqlite3_bind_int64(dStmt, 1, Int64(value.0.timeIntervalSince1970))
            _ = value.1.rawValue.withCString { cstr in
                sqlite3_bind_text(dStmt, 2, cstr, -1, Self.transient)
            }
            sqlite3_bind_int64(dStmt, 3, value.2.micrometers)
            guard sqlite3_step(dStmt) == SQLITE_DONE else {
                throw PersistenceError.other(Self.lastError(db: db))
            }
        }
    }

    private func bumpLifetime(db: OpaquePointer?, by amount: Distance) throws {
        var stmt: OpaquePointer?
        try Self.prepare(db: db, sql: """
            UPDATE lifetime_total
            SET distance_um = distance_um + ?, updated_at = strftime('%s','now')
            WHERE id = 1;
            """, into: &stmt)
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, amount.micrometers)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw PersistenceError.other(Self.lastError(db: db))
        }
    }

    private static func prepare(db: OpaquePointer?, sql: String, into stmt: inout OpaquePointer?) throws {
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if result != SQLITE_OK {
            throw PersistenceError.other(lastError(db: db))
        }
    }

    private static func exec(db: OpaquePointer?, sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &error)
        if result != SQLITE_OK {
            let msg = error.map { String(cString: $0) } ?? lastError(db: db)
            sqlite3_free(error)
            throw PersistenceError.other(msg)
        }
    }

    private static func lastError(db: OpaquePointer?) -> String {
        guard let db, let raw = sqlite3_errmsg(db) else { return "unknown sqlite error" }
        return String(cString: raw)
    }
}
