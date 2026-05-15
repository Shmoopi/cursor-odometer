import Testing
import Foundation
@testable import CursorOdometerCore

@Suite("InMemoryPersistenceStore round-trips")
struct PersistenceStoreTests {

    private func dayUTC(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = 0; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    @Test("Records and recalls a single segment by day")
    func roundTripSingleSegment() async throws {
        let store = InMemoryPersistenceStore()
        let day = dayUTC(2026, 5, 5)
        let seg = MotionSegment(
            id: 0,
            startTime: day.addingTimeInterval(3_600),
            endTime: day.addingTimeInterval(3_700),
            displayUUID: .primary,
            distance: .meters(42)
        )
        try await store.record(segments: [seg])
        #expect(await store.lifetimeTotal == .meters(42))
        let buckets = try await store.dailyBreakdown(in: day..<day.addingTimeInterval(86_400), display: nil)
        #expect(buckets.count == 1)
        #expect(buckets.first?.distance == .meters(42))
    }

    @Test("Multiple segments roll up correctly per hour and per day")
    func multipleSegmentsRollup() async throws {
        let store = InMemoryPersistenceStore()
        let day = dayUTC(2026, 5, 5)
        let segs: [MotionSegment] = [
            MotionSegment(id: 0, startTime: day.addingTimeInterval(0), endTime: day.addingTimeInterval(60),
                          displayUUID: .primary, distance: .meters(1)),
            MotionSegment(id: 0, startTime: day.addingTimeInterval(120), endTime: day.addingTimeInterval(200),
                          displayUUID: .primary, distance: .meters(2)),
            MotionSegment(id: 0, startTime: day.addingTimeInterval(7_200), endTime: day.addingTimeInterval(7_300),
                          displayUUID: .primary, distance: .meters(3))
        ]
        try await store.record(segments: segs)
        let hourly = try await store.hourlyBreakdown(in: day..<day.addingTimeInterval(86_400), display: nil)
        // Two distinct hours: 00:00 (segs 1+2 → 3 m) and 02:00 (seg 3 → 3 m).
        #expect(hourly.count == 2)
        let firstHour = hourly[0]
        let secondHour = hourly[1]
        #expect(firstHour.distance == .meters(3))
        #expect(secondHour.distance == .meters(3))
    }

    @Test("perDisplayTotals partitions by display UUID")
    func perDisplayTotals() async throws {
        let store = InMemoryPersistenceStore()
        let day = dayUTC(2026, 5, 5)
        try await store.record(segments: [
            MotionSegment(id: 0, startTime: day, endTime: day, displayUUID: DisplayUUID("a"), distance: .meters(7)),
            MotionSegment(id: 0, startTime: day, endTime: day, displayUUID: DisplayUUID("b"), distance: .meters(11))
        ])
        let totals = try await store.perDisplayTotals(in: day..<day.addingTimeInterval(86_400))
        #expect(totals[DisplayUUID("a")] == .meters(7))
        #expect(totals[DisplayUUID("b")] == .meters(11))
    }

    @Test("checkIntegrity returns .ok for an in-memory store")
    func integrityOK() async throws {
        let store = InMemoryPersistenceStore()
        let outcome = try await store.checkIntegrity()
        #expect(outcome == .ok)
    }

    @Test("resetAll empties the store")
    func resetAllEmpties() async throws {
        let store = InMemoryPersistenceStore()
        let day = dayUTC(2026, 5, 5)
        try await store.record(segments: [
            MotionSegment(id: 0, startTime: day, endTime: day, displayUUID: .primary, distance: .meters(100))
        ])
        try await store.resetAll()
        #expect(await store.lifetimeTotal == .zero)
    }

    @Test("Empty range returns zero, not nil")
    func emptyRangeZero() async throws {
        let store = InMemoryPersistenceStore()
        let day = dayUTC(2026, 5, 5)
        let total = try await store.distance(in: day..<day.addingTimeInterval(86_400), display: nil)
        #expect(total == .zero)
    }

    @Test("deleteSegments(in:) zeroes today and reduces lifetime by exactly that")
    func deleteSegmentsInRangeReducesLifetime() async throws {
        let store = InMemoryPersistenceStore()
        let yesterday = dayUTC(2026, 5, 4)
        let today = dayUTC(2026, 5, 5)
        try await store.record(segments: [
            MotionSegment(id: 0, startTime: yesterday.addingTimeInterval(120),
                          endTime: yesterday.addingTimeInterval(180),
                          displayUUID: .primary, distance: .meters(50)),
            MotionSegment(id: 0, startTime: today.addingTimeInterval(60),
                          endTime: today.addingTimeInterval(120),
                          displayUUID: .primary, distance: .meters(30))
        ])
        #expect(await store.lifetimeTotal == .meters(80))

        try await store.deleteSegments(in: today..<today.addingTimeInterval(86_400))

        let todayTotal = try await store.distance(in: today..<today.addingTimeInterval(86_400), display: nil)
        #expect(todayTotal == .zero)
        #expect(await store.lifetimeTotal == .meters(50))
        let yesterdayTotal = try await store.distance(in: yesterday..<yesterday.addingTimeInterval(86_400), display: nil)
        #expect(yesterdayTotal == .meters(50))
    }
}

@Suite("SQLitePersistenceStore on :memory:")
struct SQLitePersistenceStoreTests {

    private func dayUTC(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day
        c.hour = 0; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    @Test("SQLite store round-trips a segment and updates lifetime")
    func roundTripSingleSegment() async throws {
        let store = try SQLitePersistenceStore.inMemory()
        let day = dayUTC(2026, 5, 5)
        let seg = MotionSegment(
            id: 0,
            startTime: day.addingTimeInterval(3_600),
            endTime: day.addingTimeInterval(3_700),
            displayUUID: .primary,
            distance: .meters(42)
        )
        try await store.record(segments: [seg])
        #expect(await store.lifetimeTotal == .meters(42))
        let bucks = try await store.dailyBreakdown(in: day..<day.addingTimeInterval(86_400), display: nil)
        #expect(bucks.first?.distance == .meters(42))
    }

    @Test("SQLite store rolls up multiple deltas into one hourly+daily upsert")
    func upserts() async throws {
        let store = try SQLitePersistenceStore.inMemory()
        let day = dayUTC(2026, 5, 5)
        try await store.record(segments: [
            MotionSegment(id: 0, startTime: day, endTime: day, displayUUID: .primary, distance: .meters(1)),
            MotionSegment(id: 0, startTime: day.addingTimeInterval(60), endTime: day.addingTimeInterval(120),
                          displayUUID: .primary, distance: .meters(2))
        ])
        let buck = try await store.dailyBreakdown(in: day..<day.addingTimeInterval(86_400), display: nil)
        #expect(buck.first?.distance == .meters(3))
        #expect(await store.lifetimeTotal == .meters(3))
    }

    @Test("checkIntegrity passes on a freshly-opened store")
    func checkIntegrity() async throws {
        let store = try SQLitePersistenceStore.inMemory()
        let outcome = try await store.checkIntegrity()
        #expect(outcome == .ok)
    }

    @Test("resetAll clears all tables")
    func resetClears() async throws {
        let store = try SQLitePersistenceStore.inMemory()
        let day = dayUTC(2026, 5, 5)
        try await store.record(segments: [
            MotionSegment(id: 0, startTime: day, endTime: day, displayUUID: .primary, distance: .meters(99))
        ])
        try await store.resetAll()
        #expect(await store.lifetimeTotal == .zero)
        let buck = try await store.dailyBreakdown(in: day..<day.addingTimeInterval(86_400), display: nil)
        #expect(buck.isEmpty)
    }

    @Test("perDisplayTotals partitions across displays")
    func perDisplayTotalsAcrossDisplays() async throws {
        let store = try SQLitePersistenceStore.inMemory()
        let day = dayUTC(2026, 5, 5)
        try await store.record(segments: [
            MotionSegment(id: 0, startTime: day, endTime: day, displayUUID: DisplayUUID("a"), distance: .meters(5)),
            MotionSegment(id: 0, startTime: day, endTime: day, displayUUID: DisplayUUID("b"), distance: .meters(7))
        ])
        let totals = try await store.perDisplayTotals(in: day..<day.addingTimeInterval(86_400))
        #expect(totals[DisplayUUID("a")] == .meters(5))
        #expect(totals[DisplayUUID("b")] == .meters(7))
    }

    @Test("deleteSegments(in:) reduces lifetime and rebuilds aggregates correctly")
    func deleteSegmentsInRangeRebuildsAggregates() async throws {
        let store = try SQLitePersistenceStore.inMemory()
        let yesterday = dayUTC(2026, 5, 4)
        let today = dayUTC(2026, 5, 5)
        try await store.record(segments: [
            MotionSegment(id: 0, startTime: yesterday.addingTimeInterval(120),
                          endTime: yesterday.addingTimeInterval(180),
                          displayUUID: .primary, distance: .meters(50)),
            MotionSegment(id: 0, startTime: today.addingTimeInterval(60),
                          endTime: today.addingTimeInterval(120),
                          displayUUID: .primary, distance: .meters(30))
        ])
        #expect(await store.lifetimeTotal == .meters(80))

        try await store.deleteSegments(in: today..<today.addingTimeInterval(86_400))

        // Lifetime drops by exactly today's contribution.
        #expect(await store.lifetimeTotal == .meters(50))

        // Today's aggregates are gone.
        let todayDaily = try await store.dailyBreakdown(in: today..<today.addingTimeInterval(86_400), display: nil)
        #expect(todayDaily.isEmpty)

        // Yesterday's aggregates survive intact.
        let yesterdayDaily = try await store.dailyBreakdown(in: yesterday..<yesterday.addingTimeInterval(86_400), display: nil)
        #expect(yesterdayDaily.first?.distance == .meters(50))
    }
}
