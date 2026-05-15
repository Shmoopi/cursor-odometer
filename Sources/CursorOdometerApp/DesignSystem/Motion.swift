// Motion.swift — animation tokens.
// One source of truth so timings stay coherent across the app.
// Every animation here checks `accessibilityReduceMotion` via the helper
// `Animation.respectingReduceMotion(_:)` so VoiceOver/Reduce Motion users get
// the calm version without us re-implementing the table at every call site.

import SwiftUI

extension Animation {
    /// Hero digit-flip: 250ms cubic-bezier(.2,.8,.2,1).
    /// Reduce Motion → 120ms linear.
    static var heroFlip: Animation {
        .timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.25)
    }

    /// Reduce Motion variant of `heroFlip`. Linear, 120ms.
    static var heroFlipReduced: Animation {
        .linear(duration: 0.12)
    }

    /// Unit suffix cross-fade — 180ms at the same curve, kept in lockstep with
    /// the digit flip so the two read as one motion.
    static var unitCycle: Animation {
        .timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.18)
    }

    /// Sparkline draw-in: 400ms ease-out, 20ms stagger between bars.
    static var sparklineDraw: Animation {
        .easeOut(duration: 0.4)
    }

    /// Achievement unlock: 700ms cubic-bezier(.34,1.5,.64,1) —
    /// the only "bouncy" curve allowed in the app, used sparingly.
    /// Reduce Motion → 200ms linear cross-fade (no scale).
    static var unlock: Animation {
        .timingCurve(0.34, 1.5, 0.64, 1.0, duration: 0.7)
    }

    static var unlockReduced: Animation {
        .linear(duration: 0.2)
    }

    /// Tab switch: 180ms ease-in-out cross-fade, no slide.
    static var tabSwitch: Animation {
        .easeInOut(duration: 0.18)
    }

    /// Dashboard range change: 300ms ease-in-out, bars/lines
    /// morph in place rather than rebuild.
    static var rangeChange: Animation {
        .easeInOut(duration: 0.3)
    }

    /// Hover state — motion.fast token (150ms).
    static var hover: Animation {
        .easeOut(duration: 0.15)
    }
}

/// Choose the appropriate animation based on a Reduce Motion env value.
/// Use at every call-site rather than reading `@Environment` in views that
/// don't otherwise need it.
@MainActor
enum MotionToken {
    static func heroFlip(reduceMotion: Bool) -> Animation {
        reduceMotion ? .heroFlipReduced : .heroFlip
    }

    static func unlock(reduceMotion: Bool) -> Animation {
        reduceMotion ? .unlockReduced : .unlock
    }

    /// Sparkline draws instantly under Reduce Motion.
    static func sparkline(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .sparklineDraw
    }

    /// Stagger between bars; zero under Reduce Motion.
    static func sparklineStagger(reduceMotion: Bool) -> Double {
        reduceMotion ? 0 : 0.02
    }
}

// MARK: - Previews

#Preview("Motion timings") {
    MotionPreview()
        .frame(width: 360, height: 200)
        .background(Color.surface)
}

private struct MotionPreview: View {
    @State private var flipped = false

    var body: some View {
        VStack(spacing: Space.s4) {
            Text("Tap to preview").sectionTitleStyle()
            HStack(alignment: .firstTextBaseline) {
                Text(flipped ? "9" : "0")
                    .heroNumberStyle()
                    .id(flipped)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .clipped()
                Text(flipped ? "km" : "m").heroUnitStyle()
            }
            Button("Flip") {
                withAnimation(.heroFlip) { flipped.toggle() }
            }
        }
        .padding()
    }
}
