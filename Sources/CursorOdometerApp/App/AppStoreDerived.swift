// AppStoreDerived.swift — view-model derivations that don't deserve to clutter
// AppStore itself: achievement progress and the dashboard heatmap matrix.

import Foundation
import CursorOdometerCore

extension AppStore {

    /// Derive the achievement badges for the current state. Distance-based
    /// badges report progress toward their target; behavioral ones flip to
    /// unlocked when the corresponding state is observed.
    var achievementBadges: [AchievementBadgeViewModel] {
        let lifetime = lifetimeDistance
        let firstDate = firstSegmentDate

        return [
            AchievementBadgeViewModel(
                id: "first-day",
                title: "First Day",
                descriptor: "Welcome aboard",
                symbolName: "sun.horizon",
                isUnlocked: firstDate != nil,
                unlockedDate: firstDate,
                progress: nil
            ),
            distanceBadge(id: "1km", title: "1 km",
                          descriptor: "First kilometer",
                          symbol: "1.circle",
                          targetMeters: 1_000,
                          lifetime: lifetime),
            streakBadge(),
            distanceBadge(id: "half", title: "Half Marathon",
                          descriptor: "21.1 km of cursor",
                          symbol: "figure.walk",
                          targetMeters: 21_098,
                          lifetime: lifetime),
            distanceBadge(id: "marathon", title: "Marathon",
                          descriptor: "42.2 km of cursor",
                          symbol: "figure.run",
                          targetMeters: 42_195,
                          lifetime: lifetime),
            distanceBadge(id: "100km", title: "Centurion",
                          descriptor: "100 km of cursor",
                          symbol: "trophy",
                          targetMeters: 100_000,
                          lifetime: lifetime),
            distanceBadge(id: "1000km", title: "Cross-Continental",
                          descriptor: "1,000 km of cursor",
                          symbol: "globe.americas",
                          targetMeters: 1_000_000,
                          lifetime: lifetime),
            midnightOilBadge(),
            AchievementBadgeViewModel(
                id: "first-custom",
                title: "First Custom Unit",
                descriptor: "Defined your own ruler",
                symbolName: "ruler",
                isUnlocked: !customUnits.isEmpty,
                unlockedDate: nil,
                progress: nil
            ),
            distanceBadge(id: "equator", title: "Lap of the Equator",
                          descriptor: "40,075 km of cursor",
                          symbol: "globe",
                          targetMeters: 40_075_000,
                          lifetime: lifetime)
        ]
    }

    /// Build a 7×24 intensity matrix (rows = day-of-week, cols = hour) for
    /// the dashboard's time-of-day heatmap. Intensities are normalised to the
    /// max bucket value so the gradient always uses the full range.
    var heatmapIntensities: [[Double]] {
        var grid: [[Double]] = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        let cal = Calendar.current
        var maxValue: Double = 0
        for row in last7DaysHourly {
            let weekday = cal.component(.weekday, from: row.hour) - 1 // 0..6, Sun..Sat
            let hour = cal.component(.hour, from: row.hour)
            guard (0..<7).contains(weekday), (0..<24).contains(hour) else { continue }
            grid[weekday][hour] += row.distance.meters
            maxValue = max(maxValue, grid[weekday][hour])
        }
        guard maxValue > 0 else { return grid }
        return grid.map { row in row.map { $0 / maxValue } }
    }

    // MARK: - private builders

    private func distanceBadge(id: String,
                               title: String,
                               descriptor: String,
                               symbol: String,
                               targetMeters: Double,
                               lifetime: Distance) -> AchievementBadgeViewModel {
        let progress = min(1.0, max(0, lifetime.meters / targetMeters))
        return AchievementBadgeViewModel(
            id: id,
            title: title,
            descriptor: descriptor,
            symbolName: symbol,
            isUnlocked: progress >= 1.0,
            unlockedDate: nil,
            progress: progress >= 1.0 ? nil : progress
        )
    }

    private func streakBadge() -> AchievementBadgeViewModel {
        // 7-day streak: every day in `weeklyTrend` has > 0 distance.
        let count = weeklyTrend.count
        let nonzero = weeklyTrend.filter { $0.distance > .zero }.count
        let unlocked = count >= 7 && nonzero == count
        let progress = count == 0 ? 0 : Double(nonzero) / Double(max(count, 7))
        return AchievementBadgeViewModel(
            id: "streak-7",
            title: "7-Day Streak",
            descriptor: "Showed up daily",
            symbolName: "flame",
            isUnlocked: unlocked,
            unlockedDate: nil,
            progress: unlocked ? nil : progress
        )
    }

    private func midnightOilBadge() -> AchievementBadgeViewModel {
        let cal = Calendar.current
        let lateNight = hourlyToday.contains { row in
            let hour = cal.component(.hour, from: row.hour)
            return hour >= 0 && hour < 5 && row.distance > .zero
        }
        return AchievementBadgeViewModel(
            id: "midnight-oil",
            title: "Midnight Oil",
            descriptor: "Cursor moved between midnight and 5am",
            symbolName: "moon.stars",
            isUnlocked: lateNight,
            unlockedDate: nil,
            progress: nil
        )
    }
}
