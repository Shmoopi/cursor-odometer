// MenuBarGlyph.swift — the glyph rendered for the menu-bar status item.
// Implemented as an SF Symbol so the system can:
//   • pick the correct stroke weight for the current menu-bar height
//   • re-tint for light/dark/Tahoe Liquid Glass automatically
//   • pull the right Increased Contrast / Reduce Transparency variant
//
// The symbol is `cursorarrow.motionlines`, which reads as "this thing
// measures how much your cursor moves" with zero copy. State variants
// swap symbol names rather than overlaying paths so each state stays a
// single template image — required for crisp rendering against any wallpaper.

import SwiftUI

/// A clean SF-Symbol glyph for the menu bar. Renders as a template image
/// that the OS tints to match the menu bar's current foreground.
struct MenuBarGlyph: View {
    var size: CGFloat = 16
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: "cursorarrow.motionlines")
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.primary)
            .accessibilityHidden(true)
    }
}

/// State-aware variant. SF Symbol for tracking, slashed cursor for paused,
/// and a brief sparkle overlay for the milestone-hit confetti window.
struct MenuBarGlyphState: View {
    enum State { case tracking, paused, milestoneHit }
    var size: CGFloat = 16
    var state: State = .tracking

    var body: some View {
        switch state {
        case .tracking:
            MenuBarGlyph(size: size)
        case .paused:
            // Same shape language, but with the system's "slash" affordance
            // — universally read as "off" without a separate legend.
            Image(systemName: "cursorarrow.slash")
                .font(.system(size: size, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.primary)
                .accessibilityHidden(true)
        case .milestoneHit:
            // The base glyph plus a tiny gold spark that fades after ~6 s
            // (caller animates opacity). Two layers, both single-tint.
            ZStack(alignment: .topTrailing) {
                MenuBarGlyph(size: size)
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.colorAchievementGold)
                    .offset(x: size * 0.25, y: -size * 0.20)
            }
            .accessibilityHidden(true)
        }
    }
}

#Preview("Menu-bar glyphs") {
    HStack(spacing: Space.s4) {
        MenuBarGlyphState(size: 16, state: .tracking)
        MenuBarGlyphState(size: 16, state: .paused)
        MenuBarGlyphState(size: 16, state: .milestoneHit)
        MenuBarGlyphState(size: 22, state: .tracking)
    }
    .padding(Space.s4)
    .background(Color.surface)
}

#Preview("Menu-bar glyphs — dark") {
    HStack(spacing: Space.s4) {
        MenuBarGlyphState(size: 16, state: .tracking)
        MenuBarGlyphState(size: 16, state: .paused)
        MenuBarGlyphState(size: 16, state: .milestoneHit)
    }
    .padding(Space.s4)
    .background(Color.surface)
    .preferredColorScheme(.dark)
}
