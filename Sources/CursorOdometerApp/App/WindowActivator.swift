// WindowActivator.swift — bring app + window to the front for an `LSUIElement`
// app. SwiftUI's `openWindow` and `openSettings` create the window but do
// not activate the app or front-most the window when the activation policy
// is `.accessory`. Result: the user clicks "Settings" and the window opens
// behind whatever they were just looking at. This helper closes that gap.

import AppKit
import SwiftUI

@MainActor
enum WindowActivator {

    /// Pull the app to the front and order a SwiftUI-managed window key.
    /// `windowID` matches the `id:` you passed to `Window(_:id:)`. SwiftUI
    /// stamps that id into the window's `identifier`, so we look it up by
    /// substring match (it appears as `"SwiftUI.<id>"` or similar) and
    /// `makeKeyAndOrderFront`.
    ///
    /// Order of operations matters:
    ///   1. `openWindow` (caller) — creates the window if needed
    ///   2. `NSApp.activate` — brings our process forward despite LSUIElement
    ///   3. `makeKeyAndOrderFront` on the next runloop tick — the window
    ///      doesn't exist synchronously after `openWindow` returns
    static func bringToFront(matching windowID: String) {
        activateApp()
        // The window may not be in `NSApp.windows` until SwiftUI has had a
        // chance to vend it from the WindowGroup machinery. One tick is enough.
        DispatchQueue.main.async {
            front(matching: windowID)
        }
    }

    /// Same as `bringToFront(matching:)` but for the Settings scene, which
    /// has no caller-provided id — we match on the localized title fallback.
    static func bringSettingsToFront() {
        activateApp()
        DispatchQueue.main.async {
            // SwiftUI Settings windows expose themselves with NSWindow's
            // standard "Settings" / "Preferences" title bar. Match either.
            for window in NSApp.windows
            where window.title == "Settings"
            || window.title.hasSuffix(" Settings")
            || window.title == "Preferences" {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }
            // Fallback: any frontmost visible non-popover window will do.
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: - private

    private static func activateApp() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private static func front(matching windowID: String) {
        for window in NSApp.windows {
            let id = window.identifier?.rawValue ?? ""
            if id.contains(windowID) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }
        }
    }
}
