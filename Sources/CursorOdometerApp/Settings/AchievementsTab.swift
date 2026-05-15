// AchievementsTab.swift — vertical list, locked + unlocked mixed.
// Badge, title, one-line description, progress bar if quantitative.

import SwiftUI

struct AchievementsTab: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let badges = store.achievementBadges
        let next = badges
            .filter { !$0.isUnlocked && $0.progress != nil }
            .max(by: { ($0.progress ?? 0) < ($1.progress ?? 0) })

        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                if let next {
                    SectionHeader(title: "Next Milestone")
                    AchievementListRow(badge: next, isHighlighted: true)
                        .padding(Space.s4)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(Color.colorPrimary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .strokeBorder(Color.colorPrimary.opacity(0.18), lineWidth: 1)
                                )
                        )
                }

                SectionHeader(title: "All Achievements")

                VStack(spacing: 0) {
                    ForEach(Array(badges.enumerated()), id: \.element.id) { index, badge in
                        AchievementListRow(badge: badge, isHighlighted: false)
                            .padding(.vertical, Space.s2)
                            .padding(.horizontal, Space.s3)
                        if index < badges.count - 1 {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Color.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(Color.hairline, lineWidth: 1)
                        )
                )
            }
            .padding(Space.s4)
        }
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

private struct AchievementListRow: View {
    let badge: AchievementBadgeViewModel
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            AchievementBadgeView(model: badge, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(badge.title)
                        .font(.system(size: 13, weight: .semibold))
                    if badge.isUnlocked, let date = badge.unlockedDate {
                        Text("· unlocked \(formatted(date))")
                            .font(.metaCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                Text(badge.descriptor)
                    .font(.metaCaption)
                    .foregroundStyle(.secondary)
                if let p = badge.progress, !badge.isUnlocked {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(Color.colorPrimary)
                        .frame(maxWidth: 240)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}

#Preview("Achievements tab") {
    AchievementsTab()
        .environmentObject(AppStore.preview())
        .frame(width: 580, height: 600)
}

#Preview("Achievements tab — dark") {
    AchievementsTab()
        .environmentObject(AppStore.preview())
        .frame(width: 580, height: 600)
        .preferredColorScheme(.dark)
}
