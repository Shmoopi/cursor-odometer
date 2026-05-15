// AboutTab.swift — centered app glyph, name, version, and the local-only
// privacy callout. The header doubles as a link to shmoopi.net.

import SwiftUI
import AppKit

struct AboutTab: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Space.s5) {
                HeaderCard()
                PrivacyCallout()
                Spacer(minLength: 0)
            }
            .padding(Space.s5)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct HeaderCard: View {
    @State private var hovering = false

    private static let websiteURL = URL(string: "https://shmoopi.net/")!

    var body: some View {
        Button(action: openWebsite) {
            VStack(spacing: Space.s2) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color.colorPrimary)
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(Color.colorPrimary.opacity(hovering ? 0.16 : 0.10))
                    )
                    .padding(.bottom, Space.s1)

                Text("Cursor Odometer")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("\(versionString) · \(buildString)")
                    .font(.numeralInline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s5)
            .padding(.horizontal, Space.s4)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(hovering ? Color.colorPrimary.opacity(0.55)
                                                   : Color.hairline,
                                          lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHandCursor()
        .help("Open shmoopi.net")
        .accessibilityLabel("Cursor Odometer, version \(versionString), build \(buildString). Opens shmoopi.net.")
    }

    private func openWebsite() {
        NSWorkspace.shared.open(Self.websiteURL)
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
    private var buildString: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "build \(build)"
    }
}

private extension View {
    /// Show the macOS pointing-hand cursor while hovering, the same affordance
    /// AppKit uses for clickable links and Help-tag buttons.
    func pointingHandCursor() -> some View {
        self.onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private struct PrivacyCallout: View {
    var body: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "lock.shield")
                .font(.system(size: 20))
                .foregroundStyle(Color.colorOnTrack)
            VStack(alignment: .leading, spacing: 2) {
                Text("Local-only by design")
                    .font(.system(size: 13, weight: .semibold))
                Text("Everything stays on this Mac. No data is collected, ever.")
                    .font(.metaCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.colorOnTrack.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.colorOnTrack.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

#Preview("About tab") {
    AboutTab()
        .frame(width: 580, height: 560)
        .background(Color.surface)
}

#Preview("About tab — dark") {
    AboutTab()
        .frame(width: 580, height: 560)
        .background(Color.surface)
        .preferredColorScheme(.dark)
}
