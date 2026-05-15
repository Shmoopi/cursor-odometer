// AchievementBadgeView.swift — single badge.
// Reel-shape frame matches the brand logomark for cohesion.
// Three states: locked, unlocked, preview.
// Unlock animation is the only "bouncy" curve in the app.

import SwiftUI

/// One achievement to render. Domain logic (computing whether unlocked) lives
/// in the view-model; this view is purely presentational.
struct AchievementBadgeViewModel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let descriptor: String      // one-line explainer
    let symbolName: String      // SF Symbol
    let isUnlocked: Bool
    let unlockedDate: Date?
    /// 0…1 progress when locked, used to draw a thin progress ring on the frame.
    let progress: Double?

    init(id: String,
         title: String,
         descriptor: String,
         symbolName: String,
         isUnlocked: Bool,
         unlockedDate: Date?,
         progress: Double?) {
        self.id = id
        self.title = title
        self.descriptor = descriptor
        self.symbolName = symbolName
        self.isUnlocked = isUnlocked
        self.unlockedDate = unlockedDate
        self.progress = progress
    }

    static let sampleMarathon = AchievementBadgeViewModel(
        id: "marathon",
        title: "Marathon",
        descriptor: "42.2 km of cursor",
        symbolName: "figure.run",
        isUnlocked: false,
        unlockedDate: nil,
        progress: 0.72
    )

    static let sampleFirstDay = AchievementBadgeViewModel(
        id: "first-day",
        title: "First Day",
        descriptor: "Welcome aboard",
        symbolName: "sun.horizon",
        isUnlocked: true,
        unlockedDate: Date(),
        progress: nil
    )

    /// Static fixture used only by SwiftUI previews of `AchievementGallery`.
    /// Real running app pulls from `AppStore.achievementBadges`.
    static var sampleSet: [AchievementBadgeViewModel] {
        [
            AchievementBadgeViewModel(id: "first-day", title: "First Day",
                                      descriptor: "Welcome aboard",
                                      symbolName: "sun.horizon",
                                      isUnlocked: true,
                                      unlockedDate: Date(), progress: nil),
            AchievementBadgeViewModel(id: "1km", title: "1 km",
                                      descriptor: "First kilometer",
                                      symbolName: "1.circle",
                                      isUnlocked: true,
                                      unlockedDate: Date(), progress: nil),
            AchievementBadgeViewModel(id: "streak-7", title: "7-Day Streak",
                                      descriptor: "Showed up daily",
                                      symbolName: "flame",
                                      isUnlocked: false,
                                      unlockedDate: nil, progress: 0.4),
            AchievementBadgeViewModel(id: "marathon", title: "Marathon",
                                      descriptor: "42.2 km of cursor",
                                      symbolName: "figure.run",
                                      isUnlocked: false,
                                      unlockedDate: nil, progress: 0.72),
            AchievementBadgeViewModel(id: "100km", title: "Centurion",
                                      descriptor: "100 km of cursor",
                                      symbolName: "trophy",
                                      isUnlocked: false,
                                      unlockedDate: nil, progress: 0.30),
            AchievementBadgeViewModel(id: "equator", title: "Lap of the Equator",
                                      descriptor: "40,075 km of cursor",
                                      symbolName: "globe",
                                      isUnlocked: false,
                                      unlockedDate: nil, progress: 0.001)
        ]
    }
}

struct AchievementBadgeView: View {
    let model: AchievementBadgeViewModel
    var size: CGFloat = 64
    /// Trigger the unlock animation when this changes from false to true.
    var animateUnlock: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var unlockScale: CGFloat = 1.0
    @State private var halo: Double = 0

    var body: some View {
        ZStack {
            // Reel-shape frame (matches DigitReelLogomark)
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(model.isUnlocked ? Color.colorAchievementGold.opacity(0.18) : Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(strokeColor,
                                      style: StrokeStyle(lineWidth: model.isUnlocked ? 1.5 : 1,
                                                          dash: model.isUnlocked ? [] : [3, 3]))
                )
                .frame(width: size * 0.92, height: size)

            Image(systemName: model.symbolName)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(model.isUnlocked ? Color.colorAchievementGold : .secondary.opacity(0.4))

            // Subtle halo when unlock animates in.
            if halo > 0 {
                Circle()
                    .fill(Color.colorAchievementGold.opacity(0.2 * (1 - halo)))
                    .frame(width: size * (1 + halo), height: size * (1 + halo))
                    .allowsHitTesting(false)
            }

            // Progress ring on locked badges (only if progress is available).
            if !model.isUnlocked, let p = model.progress {
                Circle()
                    .trim(from: 0, to: p)
                    .stroke(Color.colorPrimary,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size * 0.92, height: size)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size * 1.0, height: size)
        .opacity(model.isUnlocked ? 1.0 : 0.62) // not quite the 0.38 floor — read-readability matters here
        .scaleEffect(unlockScale)
        .onChange(of: animateUnlock) { _, newValue in
            if newValue { triggerUnlock() }
        }
        .accessibilityLabel(accessibilityLabel)
        .help(helpText)
    }

    private var strokeColor: Color {
        model.isUnlocked ? Color.colorPrimary : .secondary.opacity(0.24)
    }

    private var accessibilityLabel: String {
        if model.isUnlocked {
            let f = DateFormatter()
            f.dateStyle = .medium
            let date = model.unlockedDate.map { ", unlocked " + f.string(from: $0) } ?? ", unlocked"
            return "\(model.title)\(date)"
        }
        if let p = model.progress {
            return "\(model.title), locked. \(Int((1 - p) * 100)) percent remaining."
        }
        return "\(model.title), locked."
    }

    private var helpText: String {
        model.isUnlocked ? "\(model.title): \(model.descriptor)" : "\(model.title) — \(model.descriptor)"
    }

    /// Unlock timing breakdown, used by both the bouncy and the
    /// Reduce-Motion paths so the magic numbers live in one place.
    private enum UnlockTiming {
        static let bouncePeakDelayMS: UInt64 = 700
        static let settleDurationS: Double = 0.15
        static let haloFadeDurationS: Double = 0.20
        static let haloExpandDurationS: Double = 0.40
    }

    private func triggerUnlock() {
        let timing = MotionToken.unlock(reduceMotion: reduceMotion)
        if reduceMotion {
            // 200ms cross-fade, no scale.
            withAnimation(timing) { unlockScale = 1.0 }
        } else {
            // 0.6 → 1.05 → 1.0, halo expands at 20% opacity over 400ms.
            unlockScale = 0.6
            halo = 0
            withAnimation(timing) { unlockScale = 1.05 }
            withAnimation(.easeOut(duration: UnlockTiming.haloExpandDurationS)) { halo = 0.5 }
            // Settle to 1.0 once the bouncy curve has crested. Use Task.sleep
            // rather than `DispatchQueue.main.asyncAfter` so cancellation
            // happens automatically if the view goes away mid-animation.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(UnlockTiming.bouncePeakDelayMS))
                withAnimation(.easeOut(duration: UnlockTiming.settleDurationS)) { unlockScale = 1.0 }
                withAnimation(.linear(duration: UnlockTiming.haloFadeDurationS)) { halo = 0 }
            }
        }
    }
}

#Preview("Achievement badges — sizes & states") {
    HStack(spacing: Space.s4) {
        AchievementBadgeView(model: .sampleMarathon, size: 64)
        AchievementBadgeView(model: .sampleFirstDay, size: 64)
        AchievementBadgeView(model: .sampleMarathon, size: 96)
        AchievementBadgeView(model: .sampleFirstDay, size: 96)
    }
    .padding(Space.s4)
    .background(Color.surface)
}

#Preview("Achievement badge — dark") {
    AchievementBadgeView(model: .sampleFirstDay, size: 96)
        .padding(Space.s4)
        .background(Color.surface)
        .preferredColorScheme(.dark)
}
