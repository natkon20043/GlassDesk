import AppKit
import SwiftUI
import CGlassLayout
import Observation

/// Color washes that can be mixed into every piece of glass GlassDesk draws.
enum GlassTint: String, CaseIterable, Identifiable {
    case none, ocean, sunset, mint, grape, rose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Clear"
        case .ocean: "Ocean"
        case .sunset: "Sunset"
        case .mint: "Mint"
        case .grape: "Grape"
        case .rose: "Rose"
        }
    }

    var color: Color? {
        switch self {
        case .none: nil
        case .ocean: Color(red: 0.20, green: 0.55, blue: 1.00)
        case .sunset: Color(red: 1.00, green: 0.52, blue: 0.22)
        case .mint: Color(red: 0.22, green: 0.90, blue: 0.70)
        case .grape: Color(red: 0.58, green: 0.40, blue: 1.00)
        case .rose: Color(red: 1.00, green: 0.38, blue: 0.60)
        }
    }
}

enum WidgetKind: String, CaseIterable, Identifiable {
    case clock, vitals, progress, focus, calendar, video, sound, sprite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: "Clock & Greeting"
        case .vitals: "Vitals Rings"
        case .progress: "Time Flies"
        case .focus: "Focus Timer"
        case .calendar: "Calendar"
        case .video: "YouTube Player"
        case .sound: "Sound Visualizer"
        case .sprite: "GIF Buddy"
        }
    }
}

/// Every user-facing preference, persisted to UserDefaults (domain `local.glassdesk`).
@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    @ObservationIgnored private let defaults = UserDefaults.standard

    var barEnabled: Bool { didSet { defaults.set(barEnabled, forKey: "barEnabled") } }
    var ringEnabled: Bool { didSet { defaults.set(ringEnabled, forKey: "ringEnabled") } }
    var clearGlass: Bool { didSet { defaults.set(clearGlass, forKey: "clearGlass") } }
    /// How see-through widget glass is, from 0 (full glass) to 1 (as transparent as it goes).
    var glassTransparency: Double { didSet { defaults.set(glassTransparency, forKey: "glassTransparency") } }
    /// Extra widget scaling on top of the automatic one for the screen size (1 = automatic).
    var widgetSize: Double { didSet { defaults.set(widgetSize, forKey: "widgetSize") } }
    /// A light wash inside widget cards, imitating the glass's pressed look.
    var glowEnabled: Bool { didSet { defaults.set(glowEnabled, forKey: "glowEnabled") } }
    var widgetsLocked: Bool { didSet { defaults.set(widgetsLocked, forKey: "widgetsLocked") } }
    /// The YouTube widget's controls; off shows just the video.
    var videoControls: Bool { didSet { defaults.set(videoControls, forKey: "videoControls") } }
    /// GIF Buddy height in points, and whether a still image spins.
    var spriteSize: Double { didSet { defaults.set(spriteSize, forKey: "spriteSize") } }
    var spriteSpin: Bool { didSet { defaults.set(spriteSpin, forKey: "spriteSpin") } }
    var ramEnabled: Bool { didSet { defaults.set(ramEnabled, forKey: "ramEnabled") } }
    var goblinEnabled: Bool { didSet { defaults.set(goblinEnabled, forKey: "goblinEnabled") } }
    var snapToGrid: Bool { didSet { defaults.set(snapToGrid, forKey: "snapToGrid") } }
    var tint: GlassTint { didSet { defaults.set(tint.rawValue, forKey: "tint") } }
    var enabledWidgets: Set<WidgetKind> {
        didSet { defaults.set(enabledWidgets.map(\.rawValue), forKey: "enabledWidgets") }
    }
    /// Calendar identifiers the user switched off in the ✨ menu.
    var hiddenCalendars: Set<String> {
        didSet { defaults.set(Array(hiddenCalendars), forKey: "hiddenCalendars") }
    }

    private init() {
        defaults.register(defaults: [
            "barEnabled": true,
            "ringEnabled": true,
            "clearGlass": true,
            "glassTransparency": 0.6,
            "widgetSize": 1.0,
            "glowEnabled": false,
            "widgetsLocked": false,
            "videoControls": true,
            "spriteSize": 170.0,
            "spriteSpin": true,
            "ramEnabled": true,
            "goblinEnabled": true,
            "snapToGrid": true,
            "tint": GlassTint.none.rawValue,
            "enabledWidgets": WidgetKind.allCases.map(\.rawValue),
        ])
        barEnabled = defaults.bool(forKey: "barEnabled")
        ringEnabled = defaults.bool(forKey: "ringEnabled")
        clearGlass = defaults.bool(forKey: "clearGlass")
        glassTransparency = min(max(defaults.double(forKey: "glassTransparency"), 0), 1)
        widgetSize = min(max(defaults.double(forKey: "widgetSize"), 0.5), 2.0)
        glowEnabled = defaults.bool(forKey: "glowEnabled")
        widgetsLocked = defaults.bool(forKey: "widgetsLocked")
        videoControls = defaults.bool(forKey: "videoControls")
        spriteSize = defaults.double(forKey: "spriteSize")
        spriteSpin = defaults.bool(forKey: "spriteSpin")
        ramEnabled = defaults.bool(forKey: "ramEnabled")
        goblinEnabled = defaults.bool(forKey: "goblinEnabled")
        snapToGrid = defaults.bool(forKey: "snapToGrid")
        tint = GlassTint(rawValue: defaults.string(forKey: "tint") ?? "") ?? .none
        let raw = defaults.stringArray(forKey: "enabledWidgets") ?? []
        var enabled = Set(raw.compactMap(WidgetKind.init(rawValue:)))
        // Widgets added in an update start switched on; ones the user turned off stay off.
        let known = Set((defaults.stringArray(forKey: "knownWidgets") ?? raw).compactMap(WidgetKind.init(rawValue:)))
        enabled.formUnion(Set(WidgetKind.allCases).subtracting(known))
        defaults.set(WidgetKind.allCases.map(\.rawValue), forKey: "knownWidgets")
        defaults.set(enabled.map(\.rawValue), forKey: "enabledWidgets")  // didSet doesn't run in init
        enabledWidgets = enabled
        hiddenCalendars = Set(defaults.stringArray(forKey: "hiddenCalendars") ?? [])
    }

    /// How strongly the glass is drawn over the desktop. Fading the glass layer lets more of
    /// the sharp wallpaper through, while what glass remains still bends the light at the edges.
    /// It never reaches zero, so the card edge and its refraction stay visible.
    var glassStrength: Double {
        let leastStrength = 0.12
        return 1 - glassTransparency * (1 - leastStrength)
    }

    /// The Liquid Glass material every surface uses, so tint/clarity changes apply everywhere at once.
    var glass: Glass {
        var glass: Glass = clearGlass ? .clear : .regular
        if let color = tint.color {
            glass = glass.tint(color.opacity(0.28))
        }
        return glass
    }

    /// Glass for the settings hub. It ignores the Transparency slider and Clearer Glass so the
    /// menu text always stays readable, but follows the chosen tint.
    var hubGlass: Glass {
        var glass: Glass = .regular
        if let color = tint.color {
            glass = glass.tint(color.opacity(0.28))
        }
        return glass
    }
}

/// How big widgets are drawn on a screen. Widgets are designed in points for the MacBook
/// screen (1710 x 1107 points), so a bigger screen scales them up to keep about the same
/// share of the screen instead of looking tiny. The Widget Size setting adds on top of that,
/// and the result is capped so a widget never ends up larger than the screen it is on.
///
/// The sums live in C++ (CGlassLayout), where they are tested without any UI.
@MainActor
enum WidgetScale {
    /// `naturalSize` is the widget's unscaled size including its transparent margin.
    static func factor(for screen: NSScreen, naturalSize: CGSize) -> CGFloat {
        var rules = GLScaleRules(
            baselineScreen: GLSize(width: 1710, height: 1107),
            smallestAutomatic: 0.85,
            largestAutomatic: 2.5,
            userMultiplier: Settings.shared.widgetSize,
            cardMargin: Double(WidgetController.margin),
            edgeGap: 12
        )
        let scale = gl_widget_scale(&rules,
                                    GLSize(screen.frame.size),
                                    GLSize(naturalSize),
                                    GLSize(screen.visibleFrame.size))
        return CGFloat(scale)
    }
}
