// AppStore.swift — the @MainActor view-state hub. Wires the headless core
// (sampler, aggregator, persistence) into @Published values that SwiftUI
// views subscribe to.
//
// The high-frequency loop never crosses MainActor. UI updates
// are coalesced by a 1 Hz tick that force-flushes the aggregator and pulls
// fresh aggregates from the store. The store is the only place that touches
// the persistence protocol from the UI side.

import SwiftUI
import Combine
import AppKit
import CursorOdometerCore

/// The app's root view-state. One instance, injected via `@EnvironmentObject`.
@MainActor
final class AppStore: ObservableObject {
    // MARK: Hero numbers
    @Published private(set) var todayDistance: Distance = .zero
    @Published private(set) var weekDistance: Distance = .zero
    @Published private(set) var monthDistance: Distance = .zero
    @Published private(set) var lifetimeDistance: Distance = .zero
    @Published private(set) var weeklyTrend: [DailyAggregate] = []
    @Published private(set) var dashboardDailySeries: [DailyAggregate] = []
    @Published private(set) var dashboardHourlySeries: [HourlyAggregate] = []
    @Published private(set) var hourlyToday: [HourlyAggregate] = []
    @Published private(set) var last7DaysHourly: [HourlyAggregate] = []
    @Published private(set) var perDisplayToday: [DisplayUUID: Distance] = [:]
    @Published private(set) var firstSegmentDate: Date?

    // MARK: Surface state
    @Published private(set) var displays: [DisplayInfo] = []
    @Published var settings: SettingsValues = .defaults
    @Published var customUnits: [CustomUnit] = []
    @Published var hasOnboarded: Bool = UserDefaults.standard.bool(forKey: AppStore.onboardingKey)

    // MARK: Pause/tracking
    @Published var isTrackingPaused: Bool = false
    @Published private(set) var isWarmingUp: Bool = false

    // MARK: Quick comparisons
    @Published var deltaBasis: DeltaBasis = .yesterday
    @Published private(set) var deltaValue: Distance = .zero
    @Published private(set) var deltaDirection: DeltaDirection = .neutral

    // MARK: Tab range for popover/dashboard
    @Published var popoverRange: PopoverRange = .today {
        didSet { Task { await refresh() } }
    }
    @Published var dashboardRange: DashboardRange = .week {
        didSet { Task { await refresh() } }
    }

    // MARK: Hero unit cycling (taps the unit suffix)
    @Published var heroUnitOverride: UnitPreference?

    // MARK: Dependencies (injected; previews swap these out)
    private let store: any PersistenceStoreProtocol
    private let sampler: CursorSampler?
    private let aggregator: DistanceAggregator?
    private let geometryProvider: any DisplayGeometryProviding
    private let clock: any ClockProtocol
    private var refreshTimer: Timer?

    /// Production wiring used by the `@main` app. Builds the real sampler
    /// → aggregator → SQLite chain rooted at `~/Library/Application Support`.
    /// On disk failure, falls back to an in-memory store so the app still
    /// runs (with no persistence between launches).
    static func live() -> AppStore {
        let clock = SystemClock()
        let geometry = NSScreenDisplayGeometry()
        let persistence: any PersistenceStoreProtocol
        if let url = AppStore.databaseURL(),
           let sqlite = try? SQLitePersistenceStore(url: url, clock: clock) {
            persistence = sqlite
        } else {
            persistence = InMemoryPersistenceStore()
        }
        let aggregator = DistanceAggregator(store: persistence,
                                            clock: clock,
                                            flushInterval: 0.5)
        let calculator = DistanceCalculator(geometry: geometry)
        let source = SystemEventSource()
        let sampler = CursorSampler(
            source: source,
            geometry: geometry,
            calculator: calculator,
            aggregator: aggregator,
            clock: clock
        )
        let appStore = AppStore(
            persistence: persistence,
            geometry: geometry,
            sampler: sampler,
            aggregator: aggregator,
            clock: clock
        )
        Task { await sampler.start() }
        return appStore
    }

    init(persistence: any PersistenceStoreProtocol,
         geometry: any DisplayGeometryProviding,
         sampler: CursorSampler? = nil,
         aggregator: DistanceAggregator? = nil,
         clock: any ClockProtocol = SystemClock()) {
        self.store = persistence
        self.geometryProvider = geometry
        self.sampler = sampler
        self.aggregator = aggregator
        self.clock = clock

        let detected = geometry.displays
        self.displays = detected.isEmpty ? [.previewBuiltin] : detected

        observeDisplayChanges()
        Task { await self.bootstrap() }
        startRefreshLoop()
    }

    // MARK: Lifecycle

    private func bootstrap() async {
        await refresh()
    }

    /// Pull the latest aggregates from persistence. Called on flush, on
    /// dashboard open, on tab switch, on app foreground.
    func refresh() async {
        if let aggregator = aggregator {
            try? await aggregator.flush(force: true)
        }
        do {
            let now = clock.now()
            let cal = Calendar.current
            let startOfToday = cal.startOfDay(for: now)
            let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now
            let startOfWeek = cal.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
            let startOfMonth = cal.dateInterval(of: .month, for: now)?.start ?? startOfToday
            let dashboardStart = startOfRange(dashboardRange, anchoredAt: startOfToday, calendar: cal)

            async let lifetime = store.lifetimeTotal
            async let todayValue = store.distance(in: startOfToday..<endOfToday, display: nil)
            async let weekValue = store.distance(in: startOfWeek..<endOfToday, display: nil)
            async let monthValue = store.distance(in: startOfMonth..<endOfToday, display: nil)
            async let weeklyValues = store.dailyBreakdown(in: startOfWeek..<endOfToday, display: nil)
            async let dashboardValues = store.dailyBreakdown(in: dashboardStart..<endOfToday, display: nil)
            async let hourly = store.hourlyBreakdown(in: startOfToday..<endOfToday, display: nil)
            async let weeklyHourly = store.hourlyBreakdown(in: startOfWeek..<endOfToday, display: nil)
            async let perDisplay = store.perDisplayTotals(in: startOfToday..<endOfToday)

            self.lifetimeDistance = await lifetime
            self.todayDistance = try await todayValue
            self.weekDistance = try await weekValue
            self.monthDistance = try await monthValue
            self.weeklyTrend = collapseDaily(try await weeklyValues, in: startOfWeek..<endOfToday, calendar: cal)
            self.dashboardDailySeries = collapseDaily(try await dashboardValues, in: dashboardStart..<endOfToday, calendar: cal)
            self.hourlyToday = try await hourly
            self.dashboardHourlySeries = collapseHourly(self.hourlyToday,
                                                       startOfDay: startOfToday,
                                                       now: now,
                                                       calendar: cal)
            self.last7DaysHourly = try await weeklyHourly
            self.perDisplayToday = try await perDisplay
            self.firstSegmentDate = try await earliestSegmentDate()

            self.recomputeDelta()
            self.recomputeWarmupState()
        } catch {
            // Silent failure during preview; production wiring will surface
            // a non-blocking notification.
        }
    }

    private func startRefreshLoop() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
                await self?.ensureSamplerRunning()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Watchdog that defends against state drift between the UI's
    /// `isTrackingPaused` flag and the actual sampler state. Fires every
    /// 0.5 s alongside `refresh()`. Cheap (one actor hop) and idempotent.
    ///
    /// **Why this exists:** if the OS ever drops a sleep/wake notification —
    /// or if a future code path stops the sampler without flipping the UI
    /// flag — the cursor would silently stop being measured. Without this
    /// loop, recovery would require a full app relaunch. With it, recovery
    /// happens automatically within ~500 ms.
    private func ensureSamplerRunning() async {
        guard !isTrackingPaused, let sampler = sampler else { return }
        if await !sampler.isRunning {
            await sampler.start()
        }
    }

    private func observeDisplayChanges() {
        // Block-based observer; the closure captures `self` weakly so we
        // don't need to remove it from `deinit`. The token leaks for the
        // app's lifetime, which is fine — AppStore is a singleton.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                let detected = self.geometryProvider.displays
                if !detected.isEmpty {
                    self.displays = detected
                }
            }
        }
    }

    // MARK: Derived view state

    private func recomputeDelta() {
        guard weeklyTrend.count >= 2 else {
            deltaValue = .zero
            deltaDirection = .neutral
            return
        }
        let yesterday = weeklyTrend[weeklyTrend.count - 2].distance
        let today = todayDistance
        switch deltaBasis {
        case .yesterday:
            apply(comparison: today, against: yesterday)
        case .sevenDayAvg:
            let prior = Array(weeklyTrend.dropLast())
            guard !prior.isEmpty else {
                apply(comparison: today, against: .zero); return
            }
            let totalUm = prior.reduce(Int64(0)) { $0 + $1.distance.micrometers }
            let avg = Distance(micrometers: totalUm / Int64(prior.count))
            apply(comparison: today, against: avg)
        case .personalBest:
            let best = weeklyTrend.dropLast().map(\.distance).max() ?? .zero
            apply(comparison: today, against: best)
        }
    }

    private func apply(comparison today: Distance, against baseline: Distance) {
        if today > baseline {
            deltaValue = today - baseline
            deltaDirection = .up
        } else if today < baseline {
            deltaValue = baseline - today
            deltaDirection = .down
        } else {
            deltaValue = .zero
            deltaDirection = .neutral
        }
    }

    private func recomputeWarmupState() {
        // First few seconds after install: hero shows shimmer until we have
        // any motion at all on disk.
        isWarmingUp = lifetimeDistance < Distance.millimeters(10)
    }

    private func earliestSegmentDate() async throws -> Date? {
        // The protocol doesn't expose this directly, so derive cheaply: scan
        // last-365-day daily aggregates. For users with longer histories this
        // is approximate; good enough for the "since" caption.
        let now = clock.now()
        let cal = Calendar.current
        let yearAgo = cal.date(byAdding: .day, value: -365, to: now) ?? now
        let dailies = try await store.dailyBreakdown(in: yearAgo..<now, display: nil)
        return dailies.compactMap { $0.distance > .zero ? $0.day : nil }.min()
    }

    /// Bucket the day's hourly rows (which may be sparse) into a contiguous
    /// 00:00→current-hour series. Per-display rows are summed into one row per
    /// hour so the dashboard "Today" chart draws a single smooth line, and any
    /// hours with no recorded motion are zero-filled so the curve doesn't jump.
    private func collapseHourly(_ rows: [HourlyAggregate],
                                startOfDay: Date,
                                now: Date,
                                calendar: Calendar) -> [HourlyAggregate] {
        var byHour: [Date: Distance] = [:]
        for row in rows {
            let comp = calendar.dateComponents([.year, .month, .day, .hour], from: row.hour)
            guard let key = calendar.date(from: comp) else { continue }
            byHour[key, default: .zero] += row.distance
        }
        var out: [HourlyAggregate] = []
        var cursor = startOfDay
        let nowHourComp = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let endHour = calendar.date(from: nowHourComp) ?? now
        while cursor <= endHour {
            let value = byHour[cursor] ?? .zero
            out.append(HourlyAggregate(hour: cursor, displayUUID: .primary, distance: value))
            guard let next = calendar.date(byAdding: .hour, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    private func collapseDaily(_ rows: [DailyAggregate],
                               in range: Range<Date>,
                               calendar: Calendar) -> [DailyAggregate] {
        // The protocol returns per-display rows; collapse to one row per day
        // and zero-fill missing days so the sparkline always shows the right
        // number of bars.
        var byDay: [Date: Distance] = [:]
        for row in rows {
            let key = calendar.startOfDay(for: row.day)
            byDay[key, default: .zero] += row.distance
        }
        var out: [DailyAggregate] = []
        var cursor = calendar.startOfDay(for: range.lowerBound)
        let end = calendar.startOfDay(for: range.upperBound)
        while cursor < end {
            let value = byDay[cursor] ?? .zero
            out.append(DailyAggregate(day: cursor, displayUUID: .primary, distance: value))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    private func startOfRange(_ range: DashboardRange,
                              anchoredAt today: Date,
                              calendar: Calendar) -> Date {
        switch range {
        case .day:   return today
        case .week:  return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: return calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .year:  return calendar.date(byAdding: .day, value: -364, to: today) ?? today
        }
    }

    // MARK: Sleep / wake

    /// `NSWorkspace.willSleepNotification` — system sleep imminent.
    func handleSystemSleep() {
        isTrackingPaused = true
        Task { await sampler?.stop() }
    }

    /// `NSWorkspace.didWakeNotification` — back from sleep.
    func handleSystemWake() {
        isTrackingPaused = false
        Task { await sampler?.start() }
    }

    /// `NSWorkspace.screensDidSleepNotification` — display sleep without system
    /// sleep. Treated the same as system sleep: pause and reset
    /// the baseline on the next sample.
    func handleScreensSleep() {
        isTrackingPaused = true
        Task { await sampler?.stop() }
    }

    /// `NSWorkspace.screensDidWakeNotification` — display woke (with or without
    /// a prior system-sleep cycle). Symmetric to `handleScreensSleep`: clear
    /// the paused state and restart the sampler. Without this, an overnight
    /// display-sleep event leaves tracking permanently stopped until relaunch.
    func handleScreensWake() {
        isTrackingPaused = false
        Task { await sampler?.start() }
    }

    // MARK: Onboarding

    static let onboardingKey = "net.shmoopi.cursorodometer.hasOnboarded"

    func markOnboarded() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        hasOnboarded = true
    }

    // MARK: Tracking control

    /// User pause/resume from popover or context menu.
    func setTrackingPaused(_ paused: Bool) {
        isTrackingPaused = paused
        Task {
            if paused {
                await sampler?.stop()
            } else {
                await sampler?.start()
            }
        }
    }

    func toggleTrackingPaused() {
        setTrackingPaused(!isTrackingPaused)
    }

    // MARK: Reset

    func resetToday() async {
        let now = clock.now()
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now
        if let aggregator = aggregator {
            try? await aggregator.flush(force: true)
        }
        try? await store.deleteSegments(in: startOfToday..<endOfToday)
        await refresh()
    }

    func resetAll() async {
        if let aggregator = aggregator {
            try? await aggregator.flush(force: true)
        }
        try? await store.resetAll()
        UserDefaults.standard.removeObject(forKey: Self.onboardingKey)
        hasOnboarded = false
        await refresh()
    }

    // MARK: Hero unit cycling

    func cycleHeroUnit() {
        let order = configuredUnits()
        guard !order.isEmpty else { return }
        let current = heroUnitOverride ?? settings.primaryUnit
        let idx = order.firstIndex(of: current) ?? 0
        let next = order[(idx + 1) % order.count]
        heroUnitOverride = next == settings.primaryUnit ? nil : next
    }

    /// All units the user has configured to cycle through, primary first.
    func configuredUnits() -> [UnitPreference] {
        var list: [UnitPreference] = [settings.primaryUnit]
        if let s = settings.secondaryUnit, !list.contains(s) { list.append(s) }
        for c in customUnits {
            list.append(.custom(id: c.id))
        }
        return list
    }

    /// The unit currently being shown for the hero — primary, override, or fallback.
    var activeHeroUnit: UnitPreference {
        heroUnitOverride ?? settings.primaryUnit
    }

    // MARK: Database location

    private static func databaseURL() -> URL? {
        let fm = FileManager.default
        guard let appSupport = try? fm.url(for: .applicationSupportDirectory,
                                           in: .userDomainMask,
                                           appropriateFor: nil,
                                           create: true) else { return nil }
        let dir = appSupport.appendingPathComponent("Cursor Odometer", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("odometer.sqlite")
    }
}

// MARK: - Supporting enums

enum DeltaBasis: String, CaseIterable, Hashable, Sendable {
    case yesterday
    case sevenDayAvg
    case personalBest

    var label: String {
        switch self {
        case .yesterday:    return "vs yesterday"
        case .sevenDayAvg:  return "vs 7-day avg"
        case .personalBest: return "vs personal best"
        }
    }
}

enum DeltaDirection: Hashable, Sendable {
    case up, down, neutral

    var arrow: String {
        switch self {
        case .up:      return "arrowtriangle.up.fill"
        case .down:    return "arrowtriangle.down.fill"
        case .neutral: return "minus"
        }
    }

    var word: String {
        switch self {
        case .up:      return "up"
        case .down:    return "down"
        case .neutral: return "even"
        }
    }
}

enum PopoverRange: String, CaseIterable, Hashable, Sendable {
    case today, week, month, all

    var label: String {
        switch self {
        case .today: return "Today"
        case .week:  return "Week"
        case .month: return "Month"
        case .all:   return "All"
        }
    }
}

enum DashboardRange: String, CaseIterable, Hashable, Sendable {
    case day, week, month, year

    var label: String {
        switch self {
        case .day:   return "Day"
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
        }
    }
}
