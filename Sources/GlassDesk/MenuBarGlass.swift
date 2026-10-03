import AppKit
import SwiftUI
import CGlassLayout

/// Draws Liquid Glass capsules *behind* the (transparent) native menu bar, so the real
/// menu bar keeps all of its menus and status items but gets a Dock-style glass ring.
///
/// The window sits one level below the system menu bar and ignores the mouse, so every
/// click still lands on the real menu bar. The glass is one capsule spanning the width of
/// the screen (stopping a little short of each edge), running straight behind the notch.
///
/// Where the bar goes, and whether it should be there at all, is decided by the C++ layout
/// code (CGlassLayout). This class only keeps one window per screen in step with it, and
/// re-checks whenever something could have changed the answer: displays being connected,
/// a switch of Space (a full-screen app has its own Space) or a different app coming forward.
@MainActor
final class MenuBarGlassController {
    /// Everything shown on one screen.
    private struct BarEntry {
        var window: NSWindow
        var barFrame: CGRect
        var goblin: Goblin?
        var goblinWindow: NSWindow?
    }

    private var entries: [CGDirectDisplayID: BarEntry] = [:]
    private var scheduledChecks: [DispatchWorkItem] = []
    private var observers: [NSObjectProtocol] = []

    /// Gap between the screen edges and the ends of the capsule.
    private let edgeInset: CGFloat = 8
    /// Gap between the top/bottom of the menu bar strip and the glass.
    private let verticalInset: CGFloat = 2
    /// A menu bar strip shorter than this means it is hidden on that screen.
    private let minimumBarHeight: CGFloat = 18

    init() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let triggers: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        for name in triggers {
            let observer = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshSoon()
                }
            }
            observers.append(observer)
        }
    }

    // MARK: - Updating

    /// Throws everything away and builds it again, for when a setting that shapes the bar
    /// (bar, ring or goblin on/off) has changed.
    func rebuild() {
        cancelScheduledChecks()
        for displayID in Array(entries.keys) {
            removeEntry(for: displayID)
        }
        refresh()
    }

    /// Brings the windows in line with the screens as they are right now: adds, moves and
    /// removes windows, and hides the glass on any screen whose menu bar is hidden.
    func refresh() {
        guard Settings.shared.barEnabled else {
            for displayID in Array(entries.keys) {
                removeEntry(for: displayID)
            }
            return
        }

        let hiddenMenuBarDisplays = displaysWithHiddenMenuBar()
        var connectedDisplays: Set<CGDirectDisplayID> = []

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            connectedDisplays.insert(displayID)

            let layout = gl_menu_bar_layout(GLRect(screen.frame),
                                            GLRect(screen.visibleFrame),
                                            Double(edgeInset),
                                            Double(verticalInset),
                                            Double(minimumBarHeight))
            let menuBarShown = layout.visible != 0
            let menuBarHiddenByMacOS = hiddenMenuBarDisplays.contains(displayID)

            if menuBarShown && !menuBarHiddenByMacOS {
                show(layout, on: screen, displayID: displayID)
            } else {
                // Keep nothing running for a bar nobody can see.
                removeEntry(for: displayID)
            }
        }

        for displayID in Array(entries.keys) where !connectedDisplays.contains(displayID) {
            removeEntry(for: displayID)
        }
    }

    /// Checks now, and again shortly after: macOS animates into and out of full screen, and
    /// the screen's visible frame and window list only settle when the animation ends.
    func refreshSoon() {
        cancelScheduledChecks()
        refresh()

        let delays: [TimeInterval] = [0.4, 1.2]
        for delay in delays {
            let check = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            }
            scheduledChecks.append(check)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: check)
        }
    }

    private func cancelScheduledChecks() {
        for check in scheduledChecks {
            check.cancel()
        }
        scheduledChecks.removeAll()
    }

    // MARK: - Windows

    private func show(_ layout: GLBarLayout, on screen: NSScreen, displayID: CGDirectDisplayID) {
        let barFrame = CGRect(layout.bar)
        let capsule = CGRect(layout.capsule)

        if let entry = entries[displayID], entry.barFrame == barFrame {
            // Already showing the right thing. Leave it, so the goblin isn't reset.
            if !entry.window.isVisible {
                entry.window.orderFrontRegardless()
            }
            return
        }

        // Missing, or the screen changed size: build it fresh for the new size.
        removeEntry(for: displayID)

        let window = makeGlassWindow(frame: barFrame)
        window.contentView = NSHostingView(rootView: MenuBarGlassView(capsule: capsule))
        window.setFrame(barFrame, display: true)
        window.orderFrontRegardless()

        var entry = BarEntry(window: window, barFrame: barFrame)

        // One goblin, on the screen that owns the main menu bar.
        let isPrimaryScreen = (screen == NSScreen.primary)
        if Settings.shared.goblinEnabled && isPrimaryScreen {
            addGoblin(to: &entry, above: window, bar: barFrame, capsule: capsule)
        }
        entries[displayID] = entry
    }

    private func removeEntry(for displayID: CGDirectDisplayID) {
        guard let entry = entries.removeValue(forKey: displayID) else { return }
        entry.goblin?.stop()
        entry.goblinWindow?.orderOut(nil)
        entry.window.orderOut(nil)
    }

    private func makeGlassWindow(frame: CGRect) -> NSWindow {
        let window = MenuBarGlassWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        // No .fullScreenAuxiliary: full-screen apps hide the menu bar, so hide the glass too.
        // Transient overlays hide during Mission Control and return on the selected Space.
        // Stationary windows stay above the desktop overview, exposing a frozen sprite.
        // The goblin inherits this same policy in addGoblin.
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        return window
    }

    private func addGoblin(to entry: inout BarEntry, above glass: NSWindow, bar: CGRect, capsule: CGRect) {
        let walkingRange = (capsule.minX + 18)...(capsule.maxX - 18)
        let goblin = Goblin(size: bar.size, range: walkingRange)
        // His own window above the glass, so his animation never makes WindowServer
        // re-blur the menu bar behind him.
        let window = makeGlassWindow(frame: bar)
        window.level = glass.level
        window.collectionBehavior = glass.collectionBehavior
        window.contentView = goblin.view
        window.setFrame(bar, display: true)
        window.order(.above, relativeTo: glass.windowNumber)
        entry.goblin = goblin
        entry.goblinWindow = window
    }

    // MARK: - Hidden menu bar

    /// Displays whose menu bar macOS is currently hiding, as in a full-screen app's Space.
    ///
    /// The screen's own numbers can't say: on a notched Mac a full-screen Space still
    /// reports the top strip as reserved. What does change is that macOS puts an invisible
    /// "MenuBarAgent" window, the strip's size, over every display whose menu bar is hidden
    /// (it is what notices the pointer touching the top edge). Window owners and frames are
    /// readable without any permission.
    private func displaysWithHiddenMenuBar() -> Set<CGDirectDisplayID> {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        guard let primaryScreen = NSScreen.primary else { return [] }
        let primaryHeight = primaryScreen.frame.height

        var hidden: Set<CGDirectDisplayID> = []
        for info in windowList {
            let owner = info["kCGWindowOwnerName"] as? String ?? ""
            guard owner == "MenuBarAgent" else { continue }
            guard let boundsDictionary = info["kCGWindowBounds"] as? NSDictionary,
                  let cgBounds = CGRect(dictionaryRepresentation: boundsDictionary) else { continue }

            // Window bounds have their origin at the top-left of the primary screen.
            // Screen frames have it at the bottom-left, so flip to compare them.
            let appKitBounds = CGRect(x: cgBounds.minX,
                                      y: primaryHeight - cgBounds.maxY,
                                      width: cgBounds.width,
                                      height: cgBounds.height)

            for screen in NSScreen.screens {
                guard let displayID = screen.displayID else { continue }
                let isStripOfThisScreen = gl_rect_is_top_strip(GLRect(appKitBounds), GLRect(screen.frame), 1.0)
                if isStripOfThisScreen != 0 {
                    hidden.insert(displayID)
                }
            }
        }
        return hidden
    }
}

/// AppKit normally pushes windows out of the menu bar strip; this one belongs there.
private final class MenuBarGlassWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private struct MenuBarGlassView: View {
    let capsule: CGRect

    var body: some View {
        let settings = Settings.shared
        AdjustableGlass(shape: Capsule())
            .frame(width: capsule.width, height: capsule.height)
            .overlay {
                if settings.ringEnabled { GlassRim(shape: Capsule()) }
            }
            .position(x: capsule.midX, y: capsule.midY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
