// DigitReelLogomark.swift — the brand mark ("Picked: the
// rolling-digit reel"). Three vertically-oriented digit cylinders, middle
// digit caught mid-flip, with a faint pointer-trail dot on the right.
//
// Drawn in Path so it scales cleanly from 16pt (menu-bar glyph) to 64pt
// (achievement frame) without rasterisation.

import SwiftUI

/// Brand logomark. Configurable size, optional trail dot, optional middle-digit
/// flip animation amount.
struct DigitReelLogomark: View {
    var size: CGFloat = 64
    var showTrail: Bool = true
    /// 0…1 progression of the middle digit's flip. 0 = settled, 0.5 = mid-flip.
    var flipPhase: Double = 0.5
    /// Tint for the digit reels. Defaults to primary text.
    var tint: Color = .primary

    var body: some View {
        ZStack {
            // Hairline horizon ("the track")
            HorizonLine()
                .stroke(Color.colorPrimary.opacity(0.18), lineWidth: max(0.75, size / 64))
                .frame(width: size * 1.05, height: 1)

            HStack(spacing: size * 0.04) {
                ReelDigit(digit: "3", flipProgress: 0, size: size, tint: tint)
                ReelDigit(digit: "4", flipProgress: flipPhase, size: size, tint: tint)
                ReelDigit(digit: "5", flipProgress: 0, size: size, tint: tint)
            }

            // Pointer-trail dot just below the reel right edge.
            if showTrail {
                TrailDot()
                    .frame(width: size * 0.16, height: size * 0.16)
                    .offset(x: size * 0.52, y: size * 0.32)
            }
        }
        .frame(width: size * 1.4, height: size * 0.95)
    }
}

private struct ReelDigit: View {
    let digit: String
    let flipProgress: Double  // 0 = settled, 1 = full rotation completed
    let size: CGFloat
    let tint: Color

    var body: some View {
        let cellW = size * 0.30
        let cellH = size * 0.55
        ZStack {
            RoundedRectangle(cornerRadius: cellW * 0.22, style: .continuous)
                .fill(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: cellW * 0.22, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 0.75)
                )

            // The digit, scaled and slightly translated to imply the bevel.
            Text(digit)
                .font(.system(size: cellH * 0.66, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .offset(y: flipProgress != 0 ? -cellH * 0.08 * (1 - abs(0.5 - flipProgress) * 2) : 0)

            // Top sheen — subtle Liquid Glass specular hint
            RoundedRectangle(cornerRadius: cellW * 0.22, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.18), .clear],
                                     startPoint: .top, endPoint: .center))
                .allowsHitTesting(false)
        }
        .frame(width: cellW, height: cellH)
    }
}

private struct HorizonLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

private struct TrailDot: View {
    var body: some View {
        ZStack {
            // Trail fade — three small circles to the left of the dot.
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { idx in
                    Circle()
                        .fill(Color.colorPrimary.opacity(0.18 - Double(idx) * 0.05))
                        .frame(width: 3, height: 3)
                }
                Circle()
                    .fill(Color.colorPrimary)
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Previews

#Preview("Logomark sizes") {
    VStack(spacing: Space.s4) {
        DigitReelLogomark(size: 16)
        DigitReelLogomark(size: 24)
        DigitReelLogomark(size: 32)
        DigitReelLogomark(size: 64)
    }
    .padding(Space.s4)
    .background(Color.surface)
}

#Preview("Logomark — dark") {
    VStack(spacing: Space.s4) {
        DigitReelLogomark(size: 32)
        DigitReelLogomark(size: 64)
    }
    .padding(Space.s4)
    .background(Color.surface)
    .preferredColorScheme(.dark)
}
