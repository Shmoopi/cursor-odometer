// DashboardView.swift — full window. Modern layout: a quartet
// of summary stat cards along the top, a primary range-driven chart below,
// per-display + heatmap side-by-side, then the achievement gallery.

import SwiftUI
import CursorOdometerCore

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                LifetimeHero()
                StatGrid()
                RangeChartCard()
                BreakdownCards()
                AchievementsCard()
            }
            .padding(.horizontal, Space.s6)
            .padding(.vertical, Space.s5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 1000, minHeight: 700)
        .background(Color.surface)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Image(systemName: "cursorarrow.motionlines")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.colorPrimary)
                    Text("Cursor Odometer")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, Space.s4)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.surface)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.hairline, lineWidth: 1)
                        )
                )
            }
        }
    }
}

// MARK: - Lifetime hero

private struct LifetimeHero: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let formatter = DistanceFormatter(customUnits: store.customUnits)
        let f = formatter.format(store.lifetimeDistance, in: store.activeHeroUnit)

        VStack(alignment: .leading, spacing: Space.s2) {
            Text("Lifetime")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            HeroNumberView(
                numberText: f.numberText,
                unitLabel: f.unitLabel,
                onCycleUnit: { store.cycleHeroUnit() },
                dashboardSize: true
            )

            Text(lifetimeFootnote)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var lifetimeFootnote: String {
        guard let since = store.firstSegmentDate else {
            return "Start moving — your odometer is ready."
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        let days = Calendar.current.dateComponents([.day], from: since, to: Date()).day ?? 0
        let dayWord = days == 1 ? "1 day" : "\(days) days"
        return "Since \(formatter.string(from: since)) · \(dayWord)"
    }
}

// MARK: - Stat grid (Today / Week / Month / Lifetime)

private struct StatGrid: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let formatter = DistanceFormatter(customUnits: store.customUnits)
        let unit = store.activeHeroUnit
        let cells: [StatCellModel] = [
            StatCellModel(title: "Today",
                          value: formatter.format(store.todayDistance, in: unit),
                          tint: .colorPrimary,
                          systemImage: "sun.max"),
            StatCellModel(title: "This Week",
                          value: formatter.format(store.weekDistance, in: unit),
                          tint: .colorOnTrack,
                          systemImage: "calendar"),
            StatCellModel(title: "This Month",
                          value: formatter.format(store.monthDistance, in: unit),
                          tint: .colorLifetime,
                          systemImage: "calendar.badge.clock"),
            StatCellModel(title: "All Time",
                          value: formatter.format(store.lifetimeDistance, in: unit),
                          tint: .colorAchievementGold,
                          systemImage: "infinity")
        ]
        HStack(spacing: Space.s4) {
            ForEach(cells) { cell in StatCell(model: cell) }
        }
    }
}

private struct StatCellModel: Identifiable {
    let id = UUID()
    let title: String
    let value: DistanceFormatter.Formatted
    let tint: Color
    let systemImage: String
}

private struct StatCell: View {
    let model: StatCellModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Image(systemName: model.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.tint)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(model.tint.opacity(0.10)))
                Text(model.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.value.numberText)
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .kerning(-1.0)
                    .foregroundStyle(.primary)
                Text(model.value.unitLabel)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                )
        )
        .elevation1()
    }
}

// MARK: - Range chart card

private struct RangeChartCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Distance Over Time")
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Range", selection: $store.dashboardRange) {
                    ForEach(DashboardRange.allCases, id: \.self) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()
                .frame(maxWidth: 320)
            }

            chart
                .frame(height: 260)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                )
        )
        .elevation1()
    }

    private var subtitle: String {
        switch store.dashboardRange {
        case .day:   return "Today, hour by hour."
        case .week:  return "Last seven days, day by day."
        case .month: return "Last 30 days, day by day."
        case .year:  return "Last 12 months, day by day."
        }
    }

    @ViewBuilder
    private var chart: some View {
        let unit = store.activeHeroUnit.shortLabel ?? "m"
        switch store.dashboardRange {
        case .day:
            DistanceLineChart(hourlyValues: store.dashboardHourlySeries,
                              unitLabel: unit)
        case .week, .month, .year:
            DistanceLineChart(values: store.dashboardDailySeries,
                              unitLabel: unit)
        }
    }
}

// MARK: - Breakdown cards (per-display + heatmap)

private struct BreakdownCards: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(alignment: .top, spacing: Space.s4) {
            DashboardCard(title: "Per Display",
                          subtitle: "Today's distance by monitor") {
                PerDisplayBar(totals: store.perDisplayToday, displays: store.displays)
            }

            DashboardCard(title: "Time of Day",
                          subtitle: "Last 7 days by hour & weekday") {
                TimeOfDayHeatmap(intensities: store.heatmapIntensities)
            }
        }
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                )
        )
        .elevation1()
    }
}

// MARK: - Achievements card

private struct AchievementsCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Achievements")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Earned through real cursor motion.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                let unlocked = store.achievementBadges.filter(\.isUnlocked).count
                Text("\(unlocked) / \(store.achievementBadges.count)")
                    .font(.numeralInline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            AchievementGallery(badges: store.achievementBadges)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                )
        )
        .elevation1()
    }
}

// MARK: - Previews

#Preview("Dashboard") {
    let store = AppStore.preview()
    store.markOnboarded()
    return DashboardView()
        .environmentObject(store)
        .frame(width: 1100, height: 800)
}

#Preview("Dashboard — dark") {
    let store = AppStore.preview()
    store.markOnboarded()
    return DashboardView()
        .environmentObject(store)
        .frame(width: 1100, height: 800)
        .preferredColorScheme(.dark)
}
