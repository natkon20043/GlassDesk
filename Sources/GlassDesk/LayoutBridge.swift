import AppKit
import CGlassLayout

/// Glue between AppKit's types and the plain C++ geometry in CGlassLayout.

extension GLRect {
    init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}

extension GLSize {
    init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }
}

extension CGRect {
    init(_ rect: GLRect) {
        self.init(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }
}

extension CGSize {
    init(_ size: GLSize) {
        self.init(width: size.width, height: size.height)
    }
}

extension NSScreen {
    /// The stable id of this display. It survives the screen list being reordered when a
    /// display is plugged in, which `NSScreen` identity and frames do not.
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = deviceDescription[key] as? NSNumber else { return nil }
        return number.uint32Value
    }

    /// The screen that is "primary": the one with the menu bar at launch.
    static var primary: NSScreen? {
        return NSScreen.screens.first
    }

    static func screen(withDisplayID id: CGDirectDisplayID) -> NSScreen? {
        return NSScreen.screens.first { $0.displayID == id }
    }

    /// The screen a rectangle mostly sits on, or nil if it is on none of them.
    static func screen(mostlyContaining rect: CGRect) -> NSScreen? {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for screen in NSScreen.screens {
            let overlap = screen.frame.intersection(rect)
            if overlap.isNull { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                best = screen
                bestArea = area
            }
        }
        return best
    }
}
