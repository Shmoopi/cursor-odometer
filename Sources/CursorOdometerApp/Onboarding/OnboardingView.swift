// OnboardingView.swift — single-card first-launch experience.
// App glyph, headline, "Got it" primary action.
// On dismiss, persists `hasOnboarded` to UserDefaults and cross-fades into the
// real popover via `.heroFlip`.

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var appeared = false

    var body: some View {
        VStack(spacing: Space.s4) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 56, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.colorPrimary)
                .padding(.top, Space.s5)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
                .accessibilityHidden(true)

            VStack(spacing: Space.s1) {
                Text("Your cursor has traveled.")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Let's see how far.")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .multilineTextAlignment(.center)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 4) {
                Text("Cursor Odometer measures your pointer's distance across all your displays.")
                Text("Everything stays on this Mac. No account. No network.")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.s5)
            .opacity(appeared ? 1 : 0)

            Button {
                withAnimation(MotionToken.heroFlip(reduceMotion: reduceMotion)) {
                    store.markOnboarded()
                }
            } label: {
                Text("Got it")
                    .font(.system(size: 13, weight: .medium))
                    .frame(minWidth: 100)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.colorPrimary)
            .padding(.bottom, Space.s5)
            .keyboardShortcut(.defaultAction)
        }
        .frame(width: 360)
        .background(Color.surface)
        .liquidGlassSurface(cornerRadius: 0)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    appeared = true
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Onboarding") {
    OnboardingView()
        .environmentObject(AppStore.preview(scenario: .empty))
}

#Preview("Onboarding — dark") {
    OnboardingView()
        .environmentObject(AppStore.preview(scenario: .empty))
        .preferredColorScheme(.dark)
}

#Preview("Onboarding — reduce motion") {
    OnboardingView()
        .environmentObject(AppStore.preview(scenario: .empty))
}
