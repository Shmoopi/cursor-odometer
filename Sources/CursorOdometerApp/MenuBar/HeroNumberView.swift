// HeroNumberView.swift — animated digit reel for the popover hero.
// Each digit (and the unit suffix) animates independently with `.heroFlip`.
// Tabular SF Mono Semibold, kerning -1.5, 56pt by default.
//
// Tapping the unit suffix cycles through configured units
// ("delightful interactions") — emits `onCycleUnit`.

import SwiftUI
import CursorOdometerCore

struct HeroNumberView: View {
    let numberText: String
    let unitLabel: String
    /// Emitted when the user taps the unit suffix.
    var onCycleUnit: (() -> Void)?
    /// Render the dashboard 88pt scale instead of popover 56pt.
    var dashboardSize: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: dashboardSize ? Space.s3 : Space.s2) {
            // Each character gets its own ID-driven transition so SwiftUI's
            // `.id` machinery animates the digits independently when the
            // string changes.
            FlippingNumberText(text: numberText, dashboardSize: dashboardSize)

            // Unit suffix — tappable to cycle units.
            Button {
                onCycleUnit?()
            } label: {
                Text(unitLabel)
                    .heroUnitStyle()
                    .id(unitLabel)
                    .transition(.opacity)
            }
            .buttonStyle(.plain)
            .help("Tap to cycle units")
            .accessibilityLabel("Unit: \(unitLabel). Tap to cycle.")
            .accessibilityHint("Cycles through configured units")
        }
        .heroDynamicTypeClamp()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's cursor distance, \(spellOutForVoiceOver(numberText)) \(unitLabel).")
    }

    private func spellOutForVoiceOver(_ s: String) -> String {
        // VoiceOver already speaks digits; replace decimal point with "point"
        // so "1247.3" reads "one thousand two hundred forty seven point three"
        // rather than "twelve forty seven thirty-three".
        s.replacingOccurrences(of: ".", with: " point ")
    }
}

/// Renders the digit string with each digit (or punctuation) wrapped in an
/// ID-keyed view so SwiftUI animates them independently. Pure presentation —
/// no string parsing beyond character iteration.
private struct FlippingNumberText: View {
    let text: String
    let dashboardSize: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Visual-only flip: each digit rolls in from above when the value
        // changes. Punctuation and grouping separators don't flip.
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                FlipChar(character: ch, dashboardSize: dashboardSize)
            }
        }
        .animation(MotionToken.heroFlip(reduceMotion: reduceMotion), value: text)
    }
}

private struct FlipChar: View {
    let character: Character
    let dashboardSize: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Use `.id(character)` so SwiftUI rebuilds the leaf on each change,
        // applying the move/opacity transition. Punctuation gets a no-op
        // transition so commas/decimals don't flap.
        if character.isNumber {
            Text(String(character))
                .font(dashboardSize ? .heroNumberDashboard : .heroNumber)
                .monospacedDigit()
                .kerning(dashboardSize ? -2.0 : -1.5)
                .id(character)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .clipped()
        } else {
            Text(String(character))
                .font(dashboardSize ? .heroNumberDashboard : .heroNumber)
                .monospacedDigit()
                .kerning(dashboardSize ? -2.0 : -1.5)
        }
    }
}

// MARK: - Shimmer (warm-up state)

/// "Warming up" shimmer. `--.--` glyph with a soft animated
/// gradient passing across it.
struct HeroShimmer: View {
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text("--.--")
            .heroNumberStyle()
            .foregroundStyle(.tertiary)
            .overlay(
                LinearGradient(
                    colors: [.clear, .primary.opacity(0.18), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 80)
                .offset(x: animate ? 100 : -100)
                .blendMode(.plusLighter)
                .mask(
                    Text("--.--").font(.heroNumber).monospacedDigit()
                )
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                    animate.toggle()
                }
            }
            .accessibilityLabel("Warming up. Move your cursor.")
    }
}

// MARK: - Previews

#Preview("Hero number — popover") {
    StatefulPreview()
        .padding(Space.s4)
        .frame(width: 360)
        .background(Color.surface)
}

#Preview("Hero number — dashboard") {
    HeroNumberView(numberText: "42.7", unitLabel: "km", dashboardSize: true)
        .padding(Space.s5)
        .frame(width: 600)
        .background(Color.surface)
}

#Preview("Warming up shimmer") {
    HeroShimmer()
        .padding(Space.s5)
        .frame(width: 360)
        .background(Color.surface)
}

private struct StatefulPreview: View {
    @State private var value: String = "1,247.3"
    @State private var unit: String = "m"

    var body: some View {
        VStack(spacing: Space.s4) {
            HeroNumberView(numberText: value, unitLabel: unit, onCycleUnit: cycle)
            HStack {
                Button("+") {
                    withAnimation(.heroFlip) {
                        value = "1,247.4"
                    }
                }
                Button("+10") {
                    withAnimation(.heroFlip) {
                        value = "1,257.3"
                    }
                }
                Button("Cycle unit", action: cycle)
            }
        }
    }

    func cycle() {
        withAnimation(.unitCycle) {
            unit = unit == "m" ? "km" : (unit == "km" ? "ft" : "m")
        }
    }
}
