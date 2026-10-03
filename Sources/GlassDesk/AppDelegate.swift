import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let bar = MenuBarGlassController()
    private let widgets = WidgetController()
    private let hub = SettingsHubController()
    private var statusItem: NSStatusItem?
    private var ramItem: RamStatusItem?
    private let settings = Settings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current }
        guard others.isEmpty else {
            NSApp.terminate(nil)
            return
        }

        if !UserDefaults.standard.bool(forKey: "didFirstLaunch") {
            UserDefaults.standard.set(true, forKey: "didFirstLaunch")
            LoginItem.setEnabled(true)
        }

        bar.rebuild()
        widgets.sync()
        setUpStatusItem()
        syncRamItem()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.bar.refreshSoon()
                self?.widgets.screensChanged()
            }
        }
    }

    private func syncRamItem() {
        if settings.ramEnabled, ramItem == nil {
            ramItem = RamStatusItem()
        } else if !settings.ramEnabled {
            ramItem?.remove()
            ramItem = nil
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "GlassDesk")
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item

        hub.actions = HubActions(
            rebuildBar: { [unowned self] in bar.rebuild() },
            syncWidgets: { [unowned self] in widgets.sync() },
            syncRam: { [unowned self] in syncRamItem() },
            resetPositions: { [unowned self] in widgets.resetPositions() }
        )
    }

    @objc private func statusItemClicked() {
        hub.toggle(below: statusItem?.button)
    }
}

/// NSMenuItem that runs a closure, so the menu can be built inline.
final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        state = checked ? .on : .off
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}
