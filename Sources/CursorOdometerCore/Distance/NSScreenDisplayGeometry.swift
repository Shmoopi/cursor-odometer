// NSScreenDisplayGeometry.swift — production `DisplayGeometryProviding`
// backed by `NSScreen` + `CGDisplayScreenSize`.

#if canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation

/// Production geometry provider. Reads `NSScreen.screens` once per call so
/// we always reflect the current set of attached displays — display
/// hot-plug invalidates nothing here, the next sample just re-queries.
///
/// `@unchecked Sendable` justification: this type holds no mutable state.
/// All AppKit reads happen synchronously inside each method invocation.
public final class NSScreenDisplayGeometry: DisplayGeometryProviding, @unchecked Sendable {

    public init() {}

    public var displays: [DisplayInfo] {
        let screens = NSScreen.screens
        let primary = NSScreen.main
        return screens.map { screen in
            Self.makeInfo(from: screen, isPrimary: screen == primary)
        }
    }

    public func display(at point: CGPoint) -> DisplayInfo? {
        let screens = NSScreen.screens
        let primary = NSScreen.main
        if let hit = screens.first(where: { $0.frame.contains(point) }) {
            return Self.makeInfo(from: hit, isPrimary: hit == primary)
        }
        return nil
    }

    private static func makeInfo(from screen: NSScreen, isPrimary: Bool) -> DisplayInfo {
        let displayID = displayID(for: screen)
        let uuid: DisplayUUID = displayID.flatMap { id -> DisplayUUID? in
            guard let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
            let str = CFUUIDCreateString(nil, cf) as String
            return DisplayUUID(str)
        } ?? DisplayUUID("display-\(Int(screen.frame.origin.x))-\(Int(screen.frame.origin.y))")

        let physicalSize: CGSize
        if let id = displayID {
            let mm = CGDisplayScreenSize(id)
            physicalSize = CGSize(width: mm.width, height: mm.height)
        } else {
            physicalSize = .zero
        }

        let name = (screen.localizedName.isEmpty ? "Display" : screen.localizedName)

        return DisplayInfo(
            uuid: uuid,
            displayName: name,
            frame: screen.frame,
            physicalSize: physicalSize,
            backingScaleFactor: screen.backingScaleFactor,
            isPrimary: isPrimary
        )
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        if let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return CGDirectDisplayID(n.uint32Value)
        }
        return nil
    }
}
#endif
