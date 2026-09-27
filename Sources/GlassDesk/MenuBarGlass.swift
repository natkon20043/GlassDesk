import AppKit
import SwiftUI

/// Draws Liquid Glass capsules *behind* the (transparent) native menu bar, so the real
/// menu bar keeps all of its menus and status items but gets a Dock-style glass ring.
///
/// The window sits one level below the system menu bar and ignores the mouse, so every
/// click still lands on the real menu bar. The glass is one capsule spanning the width of
/// the screen (stopping a little short of each edge), running straight behind the notch.
@MainActor
final class MenuBarGlassController {
    private var windows: [NSWindow] = []
    private var goblin: Goblin?
    private var goblinWindow: NSWindow?

    /// Gap between the screen edges and the ends of the capsule.
    private let edgeInset: CGFloat = 8
    /// Gap between the top/bottom of the menu bar strip and the glass.
    private let verticalInset: CGFloat = 2

    func rebuild() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        goblin?.stop()
        goblin = nil
        goblinWindow?.orderOut(nil)
        goblinWindow = nil
        guard Settings.shared.barEnabled else { return }
        for screen in NSScreen.screens {
            if let window = makeWindow(for: screen) {
                windows.append(window)
            }
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow? {
        let frame = screen.frame
        // Height of the menu bar strip macOS has reserved on this screen. Zero means the
        // menu bar is auto-hidden (or not shown on this display), in which case a permanent
        // glass bar would just cover app windows, so skip it.
        let barHeight = frame.maxY - screen.visibleFrame.maxY
        guard barHeight >= 18 else { return nil }

        let rect = NSRect(x: frame.minX, y: frame.maxY - barHeight, width: frame.width, height: barHeight)
        let window = MenuBarGlassWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        // No .fullScreenAuxiliary: full-screen apps hide the menu bar, so hide the glass too.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let capsule = CGRect(x: edgeInset, y: verticalInset,
                             width: frame.width - edgeInset * 2, height: barHeight - verticalInset * 2)
        window.contentView = NSHostingView(rootView: MenuBarGlassView(capsule: capsule))
        window.setFrame(rect, display: true)
        window.orderFrontRegardless()

        // One goblin, on the screen that owns the main menu bar.
        if Settings.shared.goblinEnabled, screen == NSScreen.screens.first {
            addGoblin(above: window, bar: rect, capsule: capsule)
        }
        return window
    }

    private func addGoblin(above glass: NSWindow, bar: NSRect, capsule: CGRect) {
        let goblin = Goblin(size: bar.size, range: (capsule.minX + 18)...(capsule.maxX - 18))
        // His own window above the glass, so his animation never makes WindowServer
        // re-blur the menu bar behind him.
        let window = MenuBarGlassWindow(contentRect: bar, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = glass.level
        window.collectionBehavior = glass.collectionBehavior
        window.contentView = goblin.view
        window.setFrame(bar, display: true)
        window.order(.above, relativeTo: glass.windowNumber)
        self.goblin = goblin
        goblinWindow = window
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
        Color.clear
            .frame(width: capsule.width, height: capsule.height)
            .glassEffect(settings.glass, in: .capsule)
            .overlay {
                if settings.ringEnabled { GlassRim(shape: Capsule()) }
            }
            .position(x: capsule.midX, y: capsule.midY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
