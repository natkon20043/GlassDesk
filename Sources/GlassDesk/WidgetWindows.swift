import AppKit
import SwiftUI

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
@MainActor
final class WindowMover {
    static let gridSize: CGFloat = 8

    weak var window: NSWindow?
    var onMoved: (() -> Void)?
    var onHide: (() -> Void)?

    private var start: (origin: NSPoint, mouse: NSPoint)?

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

    /// Resizes the window to its content, keeping the top edge where it is, e.g. when the
    /// video widget hides or shows its controls.
    func fit(_ size: CGSize) {
        guard let window,
              abs(window.frame.width - size.width) > 0.5 || abs(window.frame.height - size.height) > 0.5 else { return }
        var frame = window.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(frame, display: true)
        // Before the controller has placed and shown the panel its origin is meaningless,
        // and saving it would overwrite the widget's remembered spot.
        if window.isVisible { onMoved?() }
    }
}

private struct WidgetRoot: View {
    let kind: WidgetKind
    let mover: WindowMover

    var body: some View {
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: { mover.fit($0) }
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

    private var panels: [WidgetKind: WidgetPanel] = [:]
    private var occlusionObserver: NSObjectProtocol?
    private let defaults = UserDefaults.standard

    /// Opens/closes panels to match Settings, then places any widget without a saved spot.
    func sync() {
        let enabled = Settings.shared.enabledWidgets
        for kind in WidgetKind.allCases {
            if enabled.contains(kind), panels[kind] == nil {
                panels[kind] = makePanel(kind)
            } else if !enabled.contains(kind), let panel = panels.removeValue(forKey: kind) {
                panel.orderOut(nil)
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
        let layout = defaultLayout()
        for (kind, panel) in panels {
            let origin = savedOrigin(kind).flatMap { isVisible(NSRect(origin: $0, size: panel.frame.size)) ? $0 : nil }
            panel.setFrameOrigin(origin ?? layout[kind] ?? .zero)
            panel.orderFrontRegardless()
            if kind == .sound { SoundMeter.shared.setVisible(panel.occlusionState.contains(.visible)) }
        }
    }

    func resetPositions() {
        for kind in WidgetKind.allCases { defaults.removeObject(forKey: key(kind)) }
        sync()
    }

    /// After a display change, pull back any widget that ended up off every screen.
    func ensureOnScreen() {
        let layout = defaultLayout()
        for (kind, panel) in panels where !isVisible(panel.frame) {
            panel.setFrameOrigin(layout[kind] ?? .zero)
        }
    }

    private func makePanel(_ kind: WidgetKind) -> WidgetPanel {
        let mover = WindowMover()
        let hosting = FirstMouseHostingView(rootView: WidgetRoot(kind: kind, mover: mover))
        let size = hosting.fittingSize

        let panel = WidgetPanel(contentRect: NSRect(origin: .zero, size: size),
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
        mover.onMoved = { [weak self, weak panel] in
            guard let self, let panel else { return }
            self.defaults.set([panel.frame.origin.x, panel.frame.origin.y], forKey: self.key(kind))
        }
        return panel
    }

    /// Stacks cards down the right edge of the main screen (Stage Manager owns the left),
    /// starting a new column to the left whenever one fills up.
    private func defaultLayout() -> [WidgetKind: NSPoint] {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return [:] }
        let area = screen.visibleFrame.insetBy(dx: 8, dy: 4)
        let step = cardGap - Self.margin * 2  // windows overlap by their transparent margins

        var result: [WidgetKind: NSPoint] = [:]
        var columnRight = area.maxX
        var top = area.maxY
        var columnWidth: CGFloat = 0
        for kind in WidgetKind.allCases {
            guard let panel = panels[kind] else { continue }
            let size = panel.frame.size
            if top - size.height < area.minY, top < area.maxY {
                columnRight -= columnWidth + step
                top = area.maxY
                columnWidth = 0
            }
            result[kind] = NSPoint(x: columnRight - size.width, y: top - size.height)
            top -= size.height + step
            columnWidth = max(columnWidth, size.width)
        }
        return result
    }

    private func key(_ kind: WidgetKind) -> String { "widget.\(kind.rawValue).origin" }

    private func savedOrigin(_ kind: WidgetKind) -> NSPoint? {
        guard let values = defaults.array(forKey: key(kind)) as? [Double], values.count == 2 else { return nil }
        return NSPoint(x: values[0], y: values[1])
    }

    private func isVisible(_ frame: NSRect) -> Bool {
        let card = frame.insetBy(dx: Self.margin, dy: Self.margin)
        return NSScreen.screens.contains { $0.visibleFrame.intersection(card).width > 60 }
    }
}
