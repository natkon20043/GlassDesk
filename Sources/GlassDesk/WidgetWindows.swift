import AppKit
import SwiftUI
import CGlassLayout
import Observation

/// Borderless, non-activating panel that lives on the desktop layer: above the wallpaper,
/// below every normal window, on every Space.
final class WidgetPanel: NSPanel {
    /// Only widgets with text fields take the keyboard, and only while one is being typed in.
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a widget hit its buttons even though the app never activates.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Moves a window by tracking the pointer in screen coordinates, which stays stable while
/// the window (and so the view's own coordinate space) moves underneath the gesture.
///
/// It also carries the two numbers the widget and its window have to agree on: the size the
/// widget is laid out at, and how much it is drawn bigger or smaller to suit its screen.
@MainActor
@Observable
final class WindowMover {
    static let gridSize: CGFloat = 8

    /// How much the widget is drawn scaled for the screen it is on. The view watches this.
    var scale: CGFloat = 1

    /// The widget's designed size, including its transparent margin, before any scaling. The view
    /// watches it, because the window-sized frame it draws in follows it.
    var naturalSize = CGSize.zero

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var onMoved: (() -> Void)?
    @ObservationIgnored var onHide: (() -> Void)?
    @ObservationIgnored var onNaturalSizeChanged: (() -> Void)?

    @ObservationIgnored private var start: (origin: NSPoint, mouse: NSPoint)?

    func dragChanged() {
        guard !Settings.shared.widgetsLocked, let window else { return }
        let mouse = NSEvent.mouseLocation
        if start == nil { start = (window.frame.origin, mouse) }
        guard let start else { return }
        var origin = NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                             y: start.origin.y + mouse.y - start.mouse.y)
        if Settings.shared.snapToGrid {
            // A fine grid: widgets click into neat alignment without jumping far.
            origin.x = (origin.x / Self.gridSize).rounded() * Self.gridSize
            origin.y = (origin.y / Self.gridSize).rounded() * Self.gridSize
        }
        window.setFrameOrigin(origin)
    }

    func dragEnded() {
        if start != nil { onMoved?() }
        start = nil
    }

    /// Called from the widget's layout with the size it wants. A real change (the video
    /// widget hiding or showing its controls) is passed on so the window can follow.
    func reportNaturalSize(_ size: CGSize) {
        let widthChanged = abs(size.width - naturalSize.width) > 0.5
        let heightChanged = abs(size.height - naturalSize.height) > 0.5
        guard widthChanged || heightChanged else { return }
        naturalSize = size
        onNaturalSizeChanged?()
    }
}

private struct WidgetRoot: View {
    let kind: WidgetKind
    let mover: WindowMover

    var body: some View {
        let scale = mover.scale
        // The widget is laid out at its designed size, then drawn bigger or smaller to suit the
        // screen. A transform does not change layout, so the view still reports its designed size,
        // which is larger than the window when scaled down. SwiftUI centres a view that is larger
        // than its container, which shifted the card left and cut off its edge. So the window-sized
        // frame is given explicitly, and the card is pinned to its top-left corner.
        // Until the first measurement the size is unknown (zero); an explicit zero-sized frame would
        // make the widget measure as nothing, so no frame is applied until there is a size.
        let sizeKnown = mover.naturalSize.width > 0 && mover.naturalSize.height > 0
        let windowWidth: CGFloat? = sizeKnown ? mover.naturalSize.width * scale : nil
        let windowHeight: CGFloat? = sizeKnown ? mover.naturalSize.height * scale : nil

        widget
            .contextMenu {
                if kind == .sprite { SpriteMenu() }
                Button("Hide \(kind.title)") { mover.onHide?() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in mover.dragChanged() }
                    .onEnded { _ in mover.dragEnded() }
            )
            // Transparent margin so the glass shadow is not clipped by the window edge.
            .padding(WidgetController.margin)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                mover.reportNaturalSize(size)
            }
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: windowWidth, height: windowHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var widget: some View {
        if kind == .sprite {
            SpriteWidget(mover: mover)  // no card: just the cut-out floating on the desktop
        } else {
            let videoOnly = kind == .video && !Settings.shared.videoControls
            GlassCard(width: kind == .video ? VideoWidget.cardWidth : 320, padding: videoOnly ? 6 : 20) {
                switch kind {
                case .clock: ClockWidget()
                case .vitals: VitalsWidget()
                case .progress: TimeFliesWidget()
                case .focus: FocusWidget()
                case .calendar: CalendarWidget()
                case .video: VideoWidget()
                case .sound: SoundWidget()
                case .sprite: EmptyView()
                }
            }
        }
    }
}

/// Right-click options for the GIF Buddy.
private struct SpriteMenu: View {
    var body: some View {
        let store = SpriteStore.shared
        let settings = Settings.shared
        Button("Choose GIF, Image or Video…") { store.chooseFile() }
        Menu("Size") {
            ForEach([("Small", 110.0), ("Medium", 170.0), ("Large", 250.0), ("Huge", 360.0)], id: \.0) { name, height in
                Toggle(name, isOn: Binding(get: { settings.spriteSize == height }, set: { if $0 { settings.spriteSize = height } }))
            }
        }
        Toggle("Spin (still images)", isOn: Binding(get: { settings.spriteSpin }, set: { settings.spriteSpin = $0 }))
        Toggle("Remove Background", isOn: Binding(get: { store.backgroundRemoved }, set: { store.setBackgroundRemoved($0) }))
        Button("Show GIF in Finder") { store.revealInFinder() }
        Divider()
    }
}

@MainActor
final class WidgetController {
    static let margin: CGFloat = 16
    /// Visible space between neighbouring cards in the default layout.
    private let cardGap: CGFloat = 12
    /// Distance from the screen's usable edges to the default layout's first cards.
    private let defaultEdgeInset = CGSize(width: 24, height: 20)

    private var panels: [WidgetKind: WidgetPanel] = [:]
    private var movers: [WidgetKind: WindowMover] = [:]
    private var occlusionObserver: NSObjectProtocol?
    private var scheduledChecks: [DispatchWorkItem] = []
    private let defaults = UserDefaults.standard

    init() {
        watchWidgetSizeSetting()
    }

    /// Opens/closes panels to match Settings, then places and sizes every widget.
    func sync() {
        let enabled = Settings.shared.enabledWidgets
        for kind in WidgetKind.allCases {
            if enabled.contains(kind), panels[kind] == nil {
                panels[kind] = makePanel(kind)
            } else if !enabled.contains(kind), let panel = panels.removeValue(forKey: kind) {
                panel.orderOut(nil)
                movers.removeValue(forKey: kind)
                switch kind {
                case .video: VideoPlayer.shared.pause()
                case .sound:
                    SoundMeter.shared.setVisible(false)
                    occlusionObserver.map(NotificationCenter.default.removeObserver)
                    occlusionObserver = nil
                default: break
                }
            }
        }
        layoutAll()
        for (kind, panel) in panels {
            panel.orderFrontRegardless()
            if kind == .sound { SoundMeter.shared.setVisible(panel.occlusionState.contains(.visible)) }
        }
    }

    func resetPositions() {
        for kind in WidgetKind.allCases {
            defaults.removeObject(forKey: placementKey(kind))
            defaults.removeObject(forKey: legacyOriginKey(kind))
        }
        sync()
    }

    /// After a display is connected, removed or changes resolution: size every widget for the
    /// screen it belongs on and bring it fully back inside that screen. Nothing is recreated,
    /// so a playing video carries on. Runs again shortly after, because the screen's usable
    /// area keeps settling for a moment after the notification.
    func screensChanged() {
        for check in scheduledChecks { check.cancel() }
        scheduledChecks.removeAll()

        layoutAll()

        let check = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.layoutAll()
            }
        }
        scheduledChecks.append(check)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: check)
    }

    // MARK: - Panels

    private func makePanel(_ kind: WidgetKind) -> WidgetPanel {
        let mover = WindowMover()
        let hosting = FirstMouseHostingView(rootView: WidgetRoot(kind: kind, mover: mover))
        let designed = hosting.fittingSize
        mover.naturalSize = designed
        // The controller owns the window's size (the designed size times the screen's scale).
        // Left alone, the hosting view would keep resizing the window back to its own size.
        hosting.sizingOptions = []
        movers[kind] = mover

        // The size is provisional: layoutAll() sizes it for the screen it ends up on.
        let panel = WidgetPanel(contentRect: NSRect(origin: .zero, size: designed),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = hosting

        switch kind {
        case .video:
            // The link field needs typing; the panel still never activates GlassDesk.
            panel.acceptsKeyboard = true
            panel.becomesKeyOnlyIfNeeded = true
        case .sound:
            // The mic runs only while the widget can actually be seen.
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
            ) { [weak panel] _ in
                MainActor.assumeIsolated {
                    SoundMeter.shared.setVisible(panel?.occlusionState.contains(.visible) ?? false)
                }
            }
        default:
            break
        }

        mover.window = panel
        mover.onHide = { [weak self] in
            // Let the context menu finish closing before its window goes away.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Settings.shared.enabledWidgets.remove(kind)
                    self?.sync()
                }
            }
        }
        mover.onMoved = { [weak self] in
            self?.widgetWasDropped(kind)
        }
        mover.onNaturalSizeChanged = { [weak self] in
            self?.widgetChangedSize(kind)
        }
        return panel
    }

    // MARK: - Layout

    /// Sizes and places every widget. A widget the user has moved goes back to its saved
    /// spot (relative to its screen, so it also fits a screen of another size); the others
    /// are stacked down the right edge of the main screen.
    private func layoutAll() {
        guard let primary = NSScreen.primary else { return }

        // First give every widget its size, which depends only on the screen it is on.
        var unplaced: [WidgetKind] = []
        for kind in WidgetKind.allCases {
            guard panels[kind] != nil else { continue }
            let placement = savedPlacement(kind)
            let screen = placement.flatMap { NSScreen.screen(withDisplayID: $0.displayID) } ?? primary
            resize(kind, for: screen)
            if placement == nil { unplaced.append(kind) }
        }

        // Then put each one where it belongs.
        for kind in WidgetKind.allCases {
            guard let panel = panels[kind], let mover = movers[kind] else { continue }
            guard let placement = savedPlacement(kind) else { continue }
            let screen = NSScreen.screen(withDisplayID: placement.displayID) ?? primary
            let spot = GLPlacement(fractionX: placement.fractionX, fractionY: placement.fractionY)
            let cardSize = cardSize(of: panel, mover: mover)
            let card = CGRect(gl_card_from_placement(spot, GLSize(cardSize), GLRect(screen.frame)))
            let panelFrame = card.insetBy(dx: -margin(of: mover), dy: -margin(of: mover))
            panel.setFrame(clamped(panelFrame, for: mover, on: screen), display: true)
        }
        stackUnplaced(unplaced, on: primary)
    }

    private func stackUnplaced(_ kinds: [WidgetKind], on screen: NSScreen) {
        guard !kinds.isEmpty else { return }
        let area = screen.visibleFrame.insetBy(dx: defaultEdgeInset.width, dy: defaultEdgeInset.height)

        var sizes: [GLSize] = []
        for kind in kinds {
            guard let panel = panels[kind], let mover = movers[kind] else { continue }
            sizes.append(GLSize(cardSize(of: panel, mover: mover)))
        }
        var cards = [GLRect](repeating: GLRect(x: 0, y: 0, width: 0, height: 0), count: sizes.count)
        gl_stack_cards(GLRect(area), sizes, Int32(sizes.count), Double(cardGap), &cards)

        for (index, kind) in kinds.enumerated() {
            guard let panel = panels[kind], let mover = movers[kind] else { continue }
            let card = CGRect(cards[index])
            let panelFrame = card.insetBy(dx: -margin(of: mover), dy: -margin(of: mover))
            panel.setFrame(clamped(panelFrame, for: mover, on: screen), display: true)
        }
    }

    /// Chooses the scale for a screen and resizes the panel to match, keeping its top-left
    /// corner where it is (the position is fixed up by the caller).
    private func resize(_ kind: WidgetKind, for screen: NSScreen) {
        guard let panel = panels[kind], let mover = movers[kind] else { return }
        let natural = mover.naturalSize
        guard natural.width > 0, natural.height > 0 else { return }

        let scale = WidgetScale.factor(for: screen, naturalSize: natural)
        mover.scale = scale

        let newSize = CGSize(width: natural.width * scale, height: natural.height * scale)
        var frame = panel.frame
        let sizeChanged = abs(frame.width - newSize.width) > 0.5 || abs(frame.height - newSize.height) > 0.5
        guard sizeChanged else { return }
        frame.origin.y += frame.height - newSize.height
        frame.size = newSize
        panel.setFrame(frame, display: true)
    }

    /// The panel's frame moved so the card (the panel without its transparent margin) is
    /// entirely inside the screen's usable area, below the menu bar and above the Dock.
    private func clamped(_ panelFrame: CGRect, for mover: WindowMover, on screen: NSScreen) -> CGRect {
        let result = gl_clamp_panel(GLRect(panelFrame), Double(margin(of: mover)), GLRect(screen.visibleFrame))
        return CGRect(result)
    }

    private func margin(of mover: WindowMover) -> CGFloat {
        return Self.margin * mover.scale
    }

    private func cardSize(of panel: NSWindow, mover: WindowMover) -> CGSize {
        let edge = margin(of: mover) * 2
        return CGSize(width: panel.frame.width - edge, height: panel.frame.height - edge)
    }

    // MARK: - Reacting to the user

    /// A drag ended. The widget may now be on a different screen (with its own scale), so
    /// resize for that screen, pull the card fully inside it and remember the spot.
    private func widgetWasDropped(_ kind: WidgetKind) {
        guard let panel = panels[kind], let mover = movers[kind] else { return }
        guard let screen = NSScreen.screen(mostlyContaining: panel.frame) ?? NSScreen.primary else { return }

        resize(kind, for: screen)
        panel.setFrame(clamped(panel.frame, for: mover, on: screen), display: true)
        savePlacement(kind, on: screen)
    }

    /// The widget's own layout changed size, e.g. the video widget hid its controls.
    private func widgetChangedSize(_ kind: WidgetKind) {
        guard let panel = panels[kind], let mover = movers[kind] else { return }
        guard savedPlacement(kind) != nil else {
            layoutAll()  // still stacked by default: re-stack around the new size
            return
        }
        guard let screen = NSScreen.screen(mostlyContaining: panel.frame) ?? NSScreen.primary else { return }

        resize(kind, for: screen)
        panel.setFrame(clamped(panel.frame, for: mover, on: screen), display: true)
        if panel.isVisible { savePlacement(kind, on: screen) }
    }

    /// The Widget Size slider lives in Settings; re-fit everything when it moves.
    private func watchWidgetSizeSetting() {
        withObservationTracking {
            _ = Settings.shared.widgetSize
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.layoutAll()
                    self?.watchWidgetSizeSetting()
                }
            }
        }
    }

    // MARK: - Saved positions

    /// Where the user left a widget: which display, and the card's centre as a fraction of
    /// that display. Fractions (not coordinates) keep a widget in the same relative spot
    /// when the display's resolution or arrangement changes.
    private struct SavedPlacement {
        var displayID: CGDirectDisplayID
        var fractionX: Double
        var fractionY: Double
    }

    private func placementKey(_ kind: WidgetKind) -> String { "widget.\(kind.rawValue).placement" }
    private func legacyOriginKey(_ kind: WidgetKind) -> String { "widget.\(kind.rawValue).origin" }

    private func savedPlacement(_ kind: WidgetKind) -> SavedPlacement? {
        if let values = defaults.array(forKey: placementKey(kind)) as? [Double], values.count == 3 {
            return SavedPlacement(displayID: CGDirectDisplayID(values[0]), fractionX: values[1], fractionY: values[2])
        }
        return migratedLegacyPlacement(kind)
    }

    private func savePlacement(_ kind: WidgetKind, on screen: NSScreen) {
        guard let panel = panels[kind], let mover = movers[kind], let displayID = screen.displayID else { return }
        let card = CGRect(origin: panel.frame.origin, size: panel.frame.size)
            .insetBy(dx: margin(of: mover), dy: margin(of: mover))
        let spot = gl_placement_from_card(GLRect(card), GLRect(screen.frame))
        defaults.set([Double(displayID), spot.fractionX, spot.fractionY], forKey: placementKey(kind))
        defaults.removeObject(forKey: legacyOriginKey(kind))
    }

    /// Older versions saved the panel's raw origin. Convert it, if it still lies on a
    /// screen, into the new form; otherwise the widget just gets the default layout.
    private func migratedLegacyPlacement(_ kind: WidgetKind) -> SavedPlacement? {
        guard let values = defaults.array(forKey: legacyOriginKey(kind)) as? [Double], values.count == 2 else { return nil }
        guard let panel = panels[kind], let mover = movers[kind] else { return nil }

        let oldFrame = CGRect(origin: CGPoint(x: values[0], y: values[1]), size: panel.frame.size)
        guard let screen = NSScreen.screen(mostlyContaining: oldFrame), let displayID = screen.displayID else { return nil }

        let card = oldFrame.insetBy(dx: margin(of: mover), dy: margin(of: mover))
        let spot = gl_placement_from_card(GLRect(card), GLRect(screen.frame))

        // Store it in the new form now, so the conversion happens once.
        defaults.set([Double(displayID), spot.fractionX, spot.fractionY], forKey: placementKey(kind))
        defaults.removeObject(forKey: legacyOriginKey(kind))
        return SavedPlacement(displayID: displayID, fractionX: spot.fractionX, fractionY: spot.fractionY)
    }
}
