// Colors.swift — design tokens.
// "Quietly precise. Quietly playful. Quietly Mac." — every value here is the
// authoritative source for the palette. View code MUST NOT hardcode hex.

import SwiftUI

// MARK: - Light/Dark adaptive helper

extension Color {
    /// Build a color that resolves at render time from light/dark hex variants.
    /// Falls through to AppKit's `NSColor` so `Increased Contrast` and
    /// `Reduce Transparency` are honored automatically.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark,
                                                     .accessibilityHighContrastDarkAqua,
                                                     .accessibilityHighContrastVibrantDark]) != nil
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    /// Hex parser used only inside this file. SwiftUI doesn't ship one and
    /// we don't want to leak this convenience across the design system.
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

// MARK: - Brand palette (token table)

extension Color {
    /// `#3A6FF7` "Trail Blue" — saturated cobalt that feels Mac-system-adjacent
    /// without being literal `systemBlue`. Maps cleanly to `.accentColor` so
    /// system-tint users can override.
    static let trailBlue = Color.adaptive(light: 0x3A6FF7, dark: 0x6E94FF)

    /// `colorPrimary` / `colorToday` — brand, today's distance, primary actions.
    static let colorPrimary = Color.trailBlue

    /// `colorToday` — today's distance ribbon.
    static let colorToday = Color.trailBlue

    /// `colorLifetime` — all-time stats. Slightly violet-leaning to feel
    /// "deeper time" without colliding with primary actions.
    static let colorLifetime = Color.adaptive(light: 0x7A6CF0, dark: 0xA99CFF)

    /// `colorAchievementGold` — unlocked badges only. Never used for affordances.
    static let colorAchievementGold = Color.adaptive(light: 0xC99A2E, dark: 0xE8B84A)

    /// `colorDanger` — reset confirmations only. Avoid as decoration.
    static let colorDanger = Color.adaptive(light: 0xD8453B, dark: 0xFF6A60)

    /// `colorOnTrack` — positive delta. Always paired with arrow + text
    /// (color-blind safety).
    static let colorOnTrack = Color.adaptive(light: 0x34A853, dark: 0x4CC36A)

    /// `surface` — popover & dashboard background. Maps to system
    /// `controlBackgroundColor` so Liquid Glass falls back gracefully under
    /// Reduce Transparency.
    static let surface = Color(nsColor: .controlBackgroundColor)

    /// Hairline separator at 8% black/white. Increases to 1.5pt + opacity
    /// under Increased Contrast — handled in the divider modifier, not here.
    static let hairline = Color.adaptive(light: 0x000000, dark: 0xFFFFFF).opacity(0.08)
}

// MARK: - Semantic role colors

extension ShapeStyle where Self == Color {
    /// Sugar so call sites read `.fill(.todayBrand)` instead of `.fill(Color.colorToday)`.
    static var todayBrand: Color { .colorToday }
    static var lifetimeBrand: Color { .colorLifetime }
    static var achievementGold: Color { .colorAchievementGold }
}

// MARK: - Previews

#Preview("Brand swatches — light & dark") {
    HStack(spacing: 0) {
        ColorSwatchColumn(scheme: .light)
        ColorSwatchColumn(scheme: .dark)
    }
    .frame(width: 480, height: 320)
}

private struct ColorSwatchColumn: View {
    let scheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(scheme == .light ? "Light" : "Dark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(swatches, id: \.0) { name, color in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: 28, height: 18)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.hairline, lineWidth: 0.5))
                    Text(name).font(.caption.monospaced())
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surface)
        .preferredColorScheme(scheme)
    }

    private var swatches: [(String, Color)] {
        [
            ("trailBlue / colorPrimary", .trailBlue),
            ("colorLifetime", .colorLifetime),
            ("colorAchievementGold", .colorAchievementGold),
            ("colorDanger", .colorDanger),
            ("colorOnTrack", .colorOnTrack),
            ("surface", .surface),
            ("hairline", .hairline)
        ]
    }
}
