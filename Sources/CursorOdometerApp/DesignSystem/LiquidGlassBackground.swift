// LiquidGlassBackground.swift — popover & dashboard surface.
// On Tahoe (macOS 26) this becomes a Liquid Glass material with a single
// concentric rounded inset. On Sonoma (macOS 14/15) it falls back to `.menu`
// material. Under Reduce Transparency we go flat to `controlBackgroundColor`.

import SwiftUI

/// The signature surface treatment for popover & dashboard. Use as the root
/// background of those scenes; do not nest.
struct LiquidGlassBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat = Radius.lg

    var body: some View {
        ZStack {
            if reduceTransparency {
                // Flat fallback — no blur, no parallax, just an opaque control
                // background. Edge stays crisp for low-vision users.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.surface)
            } else {
                // `.regularMaterial` reads as Liquid Glass on Tahoe and `.menu`
                // on Sonoma — the system picks the right substrate per OS.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Apply the canonical Liquid Glass background. Used by popover root,
    /// dashboard root, and onboarding card.
    func liquidGlassSurface(cornerRadius: CGFloat = Radius.lg) -> some View {
        self.background(LiquidGlassBackground(cornerRadius: cornerRadius))
    }
}

#Preview("Liquid Glass background") {
    ZStack {
        // Simulated busy desktop wallpaper to test legibility.
        LinearGradient(colors: [.purple, .blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        VStack(spacing: Space.s3) {
            Text("CURSOR ODOMETER · TODAY").sectionTitleStyle()
            Text("1,247.3").heroNumberStyle()
        }
        .padding(Space.s5)
        .liquidGlassSurface()
        .frame(width: 320, height: 220)
    }
    .frame(width: 480, height: 320)
}

#Preview("Reduce Transparency fallback") {
    // NOTE: `accessibilityReduceTransparency` is a system-driven environment
    // value and not directly writable in previews. To preview the fallback,
    // toggle Reduce Transparency in System Settings, or rely on the flat
    // background path simulated below.
    VStack(spacing: Space.s3) {
        Text("CURSOR ODOMETER · TODAY").sectionTitleStyle()
        Text("1,247.3").heroNumberStyle()
    }
    .padding(Space.s5)
    .background(
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(Color.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Color.hairline, lineWidth: 1)
            )
    )
    .frame(width: 320, height: 220)
}
