// AchievementGallery.swift — grid of badges for the dashboard.
// Locked + unlocked mixed. The "next milestone" caption surfaces the closest
// locked badge so the dashboard always points the user somewhere.

import SwiftUI

struct AchievementGallery: View {
    let badges: [AchievementBadgeViewModel]
    var nextMilestoneText: String?

    init(badges: [AchievementBadgeViewModel]) {
        self.badges = badges
        self.nextMilestoneText = AchievementGallery.makeNextMilestoneText(from: badges)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("ACHIEVEMENTS").sectionTitleStyle()

            // Grid of badges. 6 columns at the dashboard width.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.s3),
                                     count: 6),
                      spacing: Space.s3) {
                ForEach(badges) { badge in
                    VStack(spacing: Space.s1) {
                        AchievementBadgeView(model: badge, size: 64)
                        Text(badge.title)
                            .font(.metaCaption)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            if let next = nextMilestoneText {
                HStack(spacing: Space.s1) {
                    Image(systemName: "arrow.forward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(next)
                        .font(.metaCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func makeNextMilestoneText(from badges: [AchievementBadgeViewModel]) -> String? {
        let nextLocked = badges
            .filter { !$0.isUnlocked && $0.progress != nil }
            .max(by: { ($0.progress ?? 0) < ($1.progress ?? 0) })
        guard let badge = nextLocked, let progress = badge.progress else { return nil }
        let remaining = max(0, 1 - progress) * 100
        let pct = Int(remaining.rounded())
        return "next: \(badge.title.lowercased()) (\(pct)% to go)"
    }
}

#Preview("Achievement gallery") {
    AchievementGallery(badges: AchievementBadgeViewModel.sampleSet)
        .frame(width: 720)
        .padding(Space.s5)
        .background(Color.surface)
}
