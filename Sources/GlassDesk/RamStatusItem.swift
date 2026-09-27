import AppKit

/// A native menu bar item showing memory use as a tiny ring gauge plus a percentage.
/// Being a real status item, it sits alongside the system icons on top of the glass.
@MainActor
final class RamStatusItem: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private let stats = SystemStats.shared
    private var shownPercent: Int?

    override init() {
        super.init()
        item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        update()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func remove() {
        timer?.invalidate()
        timer = nil
        NSStatusBar.system.removeStatusItem(item)
    }

    private func update() {
        let used = stats.memory
        let percent = Int((used * 100).rounded())
        guard percent != shownPercent else { return }
        shownPercent = percent
        item.button?.image = gauge(used)
        item.button?.title = " RAM \(percent)%"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let format = ByteCountFormatter()
        format.countStyle = .memory
        let usedBytes = Int64(stats.memory * Double(stats.memoryTotal))
        let summary = NSMenuItem(title: "Memory used: \(format.string(fromByteCount: usedBytes)) of \(format.string(fromByteCount: Int64(stats.memoryTotal)))",
                                 action: nil, keyEquivalent: "")
        summary.isEnabled = false
        menu.addItem(summary)
        menu.addItem(.separator())
        menu.addItem(ActionItem("Open Activity Monitor") {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
        })
    }

    /// Ring that fills clockwise from 12 o'clock: green when relaxed, amber when busy, red when tight.
    private func gauge(_ fraction: Double) -> NSImage {
        let color: NSColor = switch fraction {
        case ..<0.7: NSColor(red: 0.62, green: 1.00, blue: 0.22, alpha: 1)
        case ..<0.85: NSColor(red: 1.00, green: 0.80, blue: 0.20, alpha: 1)
        default: NSColor(red: 1.00, green: 0.30, blue: 0.40, alpha: 1)
        }
        return NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let track = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            track.lineWidth = 2.2
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            track.stroke()

            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: rect.width / 2 - 1.5,
                          startAngle: 90, endAngle: 90 - 360 * max(0.02, min(fraction, 1)), clockwise: true)
            arc.lineWidth = 2.2
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
            return true
        }
    }
}
