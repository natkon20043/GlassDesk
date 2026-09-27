import SwiftUI
import Observation

/// Colour washes that can be mixed into every piece of glass GlassDesk draws.
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
            "clearGlass": false,
            "glowEnabled": true,
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

    /// The Liquid Glass material every surface uses, so tint/clarity changes apply everywhere at once.
    var glass: Glass {
        var glass: Glass = clearGlass ? .clear : .regular
        if let color = tint.color {
            glass = glass.tint(color.opacity(0.28))
        }
        return glass
    }
}
