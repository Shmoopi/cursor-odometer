// Spacing.swift — component tokens.
// Multiples of 4 to align with Apple HIG. Use these constants; do not write
// magic numbers in views.

import SwiftUI

/// Spacing scale. `s1` ... `s6` map to 4 / 8 / 12 / 16 / 24 / 32 pt.
enum Space {
    /// 4pt — tight pairs (icon + label).
    static let s1: CGFloat = 4
    /// 8pt — inline groups.
    static let s2: CGFloat = 8
    /// 12pt — row padding.
    static let s3: CGFloat = 12
    /// 16pt — section padding.
    static let s4: CGFloat = 16
    /// 24pt — hero block, popover gutters.
    static let s5: CGFloat = 24
    /// 32pt — dashboard gutters.
    static let s6: CGFloat = 32
}

/// Corner radii. `sm` pills/segmented, `md` cards/inner panels, `lg` outer
/// popover/dashboard.
enum Radius {
    /// 6pt — pills, segmented control, badges.
    static let sm: CGFloat = 6
    /// 10pt — cards, inner panels, hover targets.
    static let md: CGFloat = 10
    /// 16pt — popover & dashboard outer container.
    static let lg: CGFloat = 16
}

/// Elevation tokens. Use as `.elevation1()` / `.elevation2()`
/// modifiers — the modifier respects Reduce Transparency.
struct ElevationModifier: ViewModifier {
    let level: Int
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            // Drop shadow under Reduce Transparency to keep edges crisp.
            content
        } else {
            switch level {
            case 1:
                content.shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
            case 2:
                content.shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 4)
            default:
                content
            }
        }
    }
}

extension View {
    /// Card-level shadow — elevation.1 token.
    func elevation1() -> some View { modifier(ElevationModifier(level: 1)) }

    /// Toast / unlock surface shadow — elevation.2 token.
    func elevation2() -> some View { modifier(ElevationModifier(level: 2)) }
}

// MARK: - Hairline divider

struct Hairline: View {
    @Environment(\.accessibilityShowButtonShapes) private var increasedContrast

    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: increasedContrast ? 1.5 : 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Spacing scale") {
    VStack(alignment: .leading, spacing: Space.s2) {
        ForEach([("s1", Space.s1), ("s2", Space.s2), ("s3", Space.s3),
                 ("s4", Space.s4), ("s5", Space.s5), ("s6", Space.s6)], id: \.0) { name, value in
            HStack(spacing: Space.s2) {
                Text(name).font(.numeralInline).frame(width: 32, alignment: .leading)
                Rectangle().fill(Color.trailBlue).frame(width: value, height: 16)
                Text("\(Int(value))pt").font(.metaCaption).foregroundStyle(.secondary)
            }
        }
        Hairline()
        Text("Radius progression").sectionTitleStyle()
        HStack(spacing: Space.s2) {
            ForEach([("sm", Radius.sm), ("md", Radius.md), ("lg", Radius.lg)], id: \.0) { name, value in
                VStack {
                    RoundedRectangle(cornerRadius: value)
                        .fill(Color.trailBlue.opacity(0.2))
                        .overlay(RoundedRectangle(cornerRadius: value).stroke(Color.trailBlue, lineWidth: 1))
                        .frame(width: 64, height: 48)
                    Text("\(name) · \(Int(value))pt").font(.metaCaption)
                }
            }
        }
    }
    .padding(Space.s4)
    .frame(width: 360)
    .background(Color.surface)
}
