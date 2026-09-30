import AppKit
import EventKit
import SwiftUI

// The ✨ menu bar item opens this hub instead of a plain NSMenu.
//
//   [ General ]  [   hub   ]  [ Widgets ]
//                [ Extras  ]
//
// The hub is one flat glass backplate holding three round category buttons, the
// Transparency slider, Open at Login and Quit. Choosing a category slides its own glass
// cards out of the hub: General to the left, Widgets to the right, Extras underneath on the
// left. Each side has its own fixed slot, so cards never overlap while they animate.

enum HubSection: String, CaseIterable, Identifiable {
    case general, widgets, extras

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .widgets: "Widgets"
        case .extras: "Extras"
        }
    }

    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .widgets: "square.grid.2x2"
        case .extras: "wand.and.stars"
        }
    }
}

private extension WidgetKind {
    var symbol: String {
        switch self {
        case .clock: "clock"
        case .vitals: "chart.pie"
        case .progress: "hourglass"
        case .focus: "timer"
        case .calendar: "calendar"
        case .video: "play.rectangle"
        case .sound: "waveform"
        case .sprite: "photo.on.rectangle"
        }
    }
}

/// What the hub can ask the rest of the app to do.
struct HubActions {
    var rebuildBar: () -> Void = {}
    var syncWidgets: () -> Void = {}
    var syncRam: () -> Void = {}
    var resetPositions: () -> Void = {}
}

// MARK: - Panel

private final class HubPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { close() }
}

/// Opens and closes the hub panel under the status item.
@MainActor
final class SettingsHubController {
    var actions = HubActions()

    private var panel: HubPanel?
    private var resignObserver: NSObjectProtocol?
    private var lastClosed = Date.distantPast

    func toggle(below button: NSStatusBarButton?) {
        if panel != nil {
            close()
            return
        }
        // Clicking the status item takes key status from the open hub, which closes it. That
        // same click must not open it straight again.
        guard Date().timeIntervalSince(lastClosed) > 0.3 else { return }
        open(below: button)
    }

    private func open(below button: NSStatusBarButton?) {
        let size = HubView.panelSize
        let hosting = FirstMouseHostingView(rootView: HubView(actions: actions, dismiss: { [weak self] in self?.close() }))

        let panel = HubPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = hosting
        panel.setFrameOrigin(origin(for: size, below: button))
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func close() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
        lastClosed = Date()
    }

    /// Centres the panel under the status item, then keeps it fully on the screen. The panel
    /// has room on both sides of the hub for the flyout cards, so near the screen's right
    /// edge that pulls the hub a little to the left of its icon.
    private func origin(for size: CGSize, below button: NSStatusBarButton?) -> NSPoint {
        let buttonFrame = button?.window?.frame ?? .zero
        let screen = button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame

        var x = buttonFrame.midX - size.width / 2
        let leftLimit = visible.minX + 8
        let rightLimit = visible.maxX - size.width - 8
        x = max(leftLimit, min(x, rightLimit))

        let top = visible.maxY - 6
        return NSPoint(x: x, y: top - size.height)
    }
}

// MARK: - Layout

struct HubView: View {
    static let hubWidth: CGFloat = 300
    static let flyoutWidth: CGFloat = 264
    static let gap: CGFloat = 14
    static let panelHeight: CGFloat = 700
    static var panelSize: CGSize {
        CGSize(width: flyoutWidth * 2 + hubWidth + gap * 2 + 32, height: panelHeight)
    }

    let actions: HubActions
    let dismiss: () -> Void

    @State private var openSection: HubSection?

    var body: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            HStack(alignment: .top, spacing: Self.gap) {
                flyoutSlot(.general, alignment: .topTrailing, grow: .trailing)
                HubBackplate(openSection: openSection, choose: choose)
                    .frame(width: Self.hubWidth)
                flyoutSlot(.widgets, alignment: .topLeading, grow: .leading)
            }
            HStack(alignment: .top, spacing: 0) {
                Spacer().frame(width: Self.flyoutWidth + Self.gap)
                flyoutSlot(.extras, alignment: .topLeading, grow: .top)
            }
        }
        .padding(16)
        .frame(width: Self.panelSize.width, height: Self.panelSize.height, alignment: .topLeading)
        .background {
            // Clicking the empty area around the cards closes the hub.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
        }
    }

    private func choose(_ section: HubSection) {
        withAnimation(.spring(duration: 0.38, bounce: 0.22)) {
            openSection = (openSection == section) ? nil : section
        }
    }

    /// A fixed-size place beside the hub. Its card grows out of the edge that touches the hub.
    private func flyoutSlot(_ section: HubSection, alignment: Alignment, grow: UnitPoint) -> some View {
        ZStack(alignment: alignment) {
            if openSection == section {
                HubFlyout(section: section, actions: actions)
                    .frame(width: Self.flyoutWidth)
                    .transition(.scale(scale: 0.86, anchor: grow).combined(with: .opacity))
            }
        }
        .frame(width: Self.flyoutWidth, alignment: alignment)
    }
}

// MARK: - The hub itself

private struct HubBackplate: View {
    let openSection: HubSection?
    let choose: (HubSection) -> Void

    @Bindable private var settings = Settings.shared
    @State private var launchesAtLogin = LoginItem.isEnabled

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text("GlassDesk")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 6)

            HStack(spacing: 20) {
                ForEach(HubSection.allCases) { section in
                    CategoryButton(section: section, selected: openSection == section) { choose(section) }
                }
            }

            transparencyControl

            Divider().opacity(0.5)

            VStack(spacing: 2) {
                HubRow(title: "Open at Login", checked: launchesAtLogin) {
                    LoginItem.setEnabled(!LoginItem.isEnabled)
                    launchesAtLogin = LoginItem.isEnabled
                }
                HubRow(title: "Quit GlassDesk", symbol: "power") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassEffect(settings.hubGlass, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var transparencyControl: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Transparency")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int((settings.glassTransparency * 100).rounded()))%")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $settings.glassTransparency, in: 0...1)
                .controlSize(.small)
        }
        .padding(.horizontal, 6)
    }
}

private struct CategoryButton: View {
    let section: HubSection
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let glass: Glass = selected ? .regular.tint(Color.accentColor.opacity(0.55)).interactive() : .regular.interactive()
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: section.symbol)
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 62, height: 62)
                    .glassEffect(glass, in: .circle)
                Text(section.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flyout cards

private struct HubFlyout: View {
    let section: HubSection
    let actions: HubActions

    var body: some View {
        // Each block is its own piece of glass; the container lets neighbouring pieces blend
        // like liquid instead of stacking hard edges.
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 10) {
                switch section {
                case .general: GeneralCards(actions: actions)
                case .widgets: WidgetCards(actions: actions)
                case .extras: ExtraCards(actions: actions)
                }
            }
        }
    }
}

private struct GeneralCards: View {
    let actions: HubActions
    @Bindable private var settings = Settings.shared

    var body: some View {
        HubCard(title: "Glass") {
            HubRow(title: "Glass Menu Bar", symbol: "menubar.rectangle", checked: settings.barEnabled) {
                settings.barEnabled.toggle()
                actions.rebuildBar()
            }
            HubRow(title: "Bright Ring", symbol: "circle.dashed", checked: settings.ringEnabled) {
                settings.ringEnabled.toggle()
            }
            HubRow(title: "Clearer Glass", symbol: "drop", checked: settings.clearGlass) {
                settings.clearGlass.toggle()
            }
            HubRow(title: "Light Glow", symbol: "sun.max", checked: settings.glowEnabled) {
                settings.glowEnabled.toggle()
            }
        }
        HubCard(title: "Tint") {
            TintPicker()
        }
    }
}

private struct WidgetCards: View {
    let actions: HubActions
    @Bindable private var settings = Settings.shared

    var body: some View {
        HubCard(title: "Show on Desktop") {
            ForEach(WidgetKind.allCases) { kind in
                HubRow(title: kind.title, symbol: kind.symbol, checked: settings.enabledWidgets.contains(kind)) {
                    if settings.enabledWidgets.contains(kind) {
                        settings.enabledWidgets.remove(kind)
                    } else {
                        settings.enabledWidgets.insert(kind)
                    }
                    actions.syncWidgets()
                }
            }
            HubRow(title: "Show Video Controls", symbol: "slider.horizontal.below.rectangle", checked: settings.videoControls) {
                settings.videoControls.toggle()
            }
        }
        HubCard(title: "Size") {
            WidgetSizeSlider()
        }
        HubCard(title: "Positions") {
            HubRow(title: "Lock Widget Positions", symbol: "lock", checked: settings.widgetsLocked) {
                settings.widgetsLocked.toggle()
            }
            HubRow(title: "Snap Widgets to Grid", symbol: "grid", checked: settings.snapToGrid) {
                settings.snapToGrid.toggle()
            }
            HubRow(title: "Reset Widget Positions", symbol: "arrow.counterclockwise") {
                actions.resetPositions()
            }
        }
    }
}

private struct ExtraCards: View {
    let actions: HubActions
    @Bindable private var settings = Settings.shared

    var body: some View {
        HubCard(title: "Menu Bar") {
            HubRow(title: "Goblin", symbol: "figure.walk", checked: settings.goblinEnabled) {
                settings.goblinEnabled.toggle()
                actions.rebuildBar()
            }
            HubRow(title: "RAM in Menu Bar", symbol: "memorychip", checked: settings.ramEnabled) {
                settings.ramEnabled.toggle()
                actions.syncRam()
            }
        }
        HubCard(title: "Calendars") {
            CalendarRows()
        }
    }
}

// MARK: - Pieces

/// One block of glass with a small heading, holding a group of rows.
private struct HubCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 3)
            content
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(Settings.shared.hubGlass, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
    }
}

/// A single clickable line. A tick on the left shows a switch that is on, and an icon on
/// the right says what the line is about, like the rows of a context menu.
private struct HubRow: View {
    let title: String
    var symbol: String?
    var dotColor: Color?
    var checked: Bool?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 14)
                    .opacity(checked == true ? 1 : 0)
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 9, height: 9)
                }
                Text(title)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(hovering ? 0.16 : 0))
        )
        .onHover { hovering = $0 }
    }
}

/// Fine-tunes widget size on top of the automatic sizing for the screen.
private struct WidgetSizeSlider: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Widget Size")
                    .font(.system(size: 13.5))
                Spacer()
                Text("\(Int((settings.widgetSize * 100).rounded()))%")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $settings.widgetSize, in: 0.5...2.0)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct TintPicker: View {
    @Bindable private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 10) {
            ForEach(GlassTint.allCases) { tint in
                let selected = settings.tint == tint
                Button {
                    settings.tint = tint
                } label: {
                    Circle()
                        .fill(tint.color ?? Color.white.opacity(0.35))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 0.75))
                        .overlay(Circle().strokeBorder(.white, lineWidth: selected ? 2 : 0).padding(-4))
                }
                .buttonStyle(.plain)
                .help(tint.title)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalendarRows: View {
    @Bindable private var settings = Settings.shared
    private let store = CalendarStore.shared

    var body: some View {
        switch store.access {
        case .granted:
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(store.calendarsByAccount, id: \.account) { group in
                        Text(group.account)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                            calendarRow(calendar)
                        }
                    }
                }
            }
            .frame(maxHeight: 190)
            HubRow(title: "Add Account…", symbol: "person.badge.plus") {
                CalendarStore.openInternetAccounts()
            }
        case .notDetermined:
            HubRow(title: "Allow Calendar Access…", symbol: "calendar.badge.checkmark") {
                store.requestAccess()
            }
        case .denied:
            HubRow(title: "Open Privacy Settings…", symbol: "hand.raised") {
                CalendarStore.openPrivacySettings()
            }
        }
    }

    private func calendarRow(_ calendar: EKCalendar) -> some View {
        let id = calendar.calendarIdentifier
        let visible = !settings.hiddenCalendars.contains(id)
        return HubRow(title: calendar.title, dotColor: Color(nsColor: calendar.color), checked: visible) {
            if visible {
                settings.hiddenCalendars.insert(id)
            } else {
                settings.hiddenCalendars.remove(id)
            }
            store.reload()
        }
    }
}
