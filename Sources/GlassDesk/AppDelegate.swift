import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let bar = MenuBarGlassController()
    private let widgets = WidgetController()
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
                self?.bar.rebuild()
                self?.widgets.ensureOnScreen()
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

    // MARK: - Status menu

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "GlassDesk")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "GlassDesk", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(ActionItem("Glass Menu Bar", checked: settings.barEnabled) { [unowned self] in
            settings.barEnabled.toggle()
            bar.rebuild()
        })
        menu.addItem(ActionItem("Bright Ring", checked: settings.ringEnabled) { [unowned self] in
            settings.ringEnabled.toggle()
        })
        menu.addItem(ActionItem("Clearer Glass", checked: settings.clearGlass) { [unowned self] in
            settings.clearGlass.toggle()
        })
        menu.addItem(ActionItem("Light Glow", checked: settings.glowEnabled) { [unowned self] in
            settings.glowEnabled.toggle()
        })
        menu.addItem(ActionItem("Goblin", checked: settings.goblinEnabled) { [unowned self] in
            settings.goblinEnabled.toggle()
            bar.rebuild()
        })
        menu.addItem(ActionItem("RAM in Menu Bar", checked: settings.ramEnabled) { [unowned self] in
            settings.ramEnabled.toggle()
            syncRamItem()
        })

        let tintMenu = NSMenu()
        for tint in GlassTint.allCases {
            let item = ActionItem(tint.title, checked: settings.tint == tint) { [unowned self] in
                settings.tint = tint
            }
            item.image = swatch(tint.color.map { NSColor($0) })
            tintMenu.addItem(item)
        }
        let tintItem = NSMenuItem(title: "Tint", action: nil, keyEquivalent: "")
        tintItem.submenu = tintMenu
        menu.addItem(tintItem)

        menu.addItem(.separator())

        // Every widget listed right in the menu (not a submenu) so each is one click to hide.
        let widgetsHeader = NSMenuItem(title: "Widgets (right-click a widget to hide it)", action: nil, keyEquivalent: "")
        widgetsHeader.isEnabled = false
        menu.addItem(widgetsHeader)
        for kind in WidgetKind.allCases {
            let item = ActionItem(kind.title, checked: settings.enabledWidgets.contains(kind)) { [unowned self] in
                if settings.enabledWidgets.contains(kind) {
                    settings.enabledWidgets.remove(kind)
                } else {
                    settings.enabledWidgets.insert(kind)
                }
                widgets.sync()
            }
            item.indentationLevel = 1
            menu.addItem(item)
        }
        let videoControls = ActionItem("Show Video Controls", checked: settings.videoControls) { [unowned self] in
            settings.videoControls.toggle()
        }
        videoControls.indentationLevel = 1
        menu.addItem(videoControls)
        menu.addItem(.separator())

        menu.addItem(calendarsItem())
        menu.addItem(ActionItem("Lock Widget Positions", checked: settings.widgetsLocked) { [unowned self] in
            settings.widgetsLocked.toggle()
        })
        menu.addItem(ActionItem("Snap Widgets to Grid", checked: settings.snapToGrid) { [unowned self] in
            settings.snapToGrid.toggle()
        })
        menu.addItem(ActionItem("Reset Widget Positions") { [unowned self] in
            widgets.resetPositions()
        })

        menu.addItem(.separator())

        menu.addItem(ActionItem("Open at Login", checked: LoginItem.isEnabled) {
            LoginItem.setEnabled(!LoginItem.isEnabled)
        })
        menu.addItem(ActionItem("Quit GlassDesk", key: "q") {
            NSApp.terminate(nil)
        })
    }

    /// Per-calendar on/off switches, grouped by account, plus a shortcut for adding accounts.
    private func calendarsItem() -> NSMenuItem {
        let store = CalendarStore.shared
        let submenu = NSMenu()
        switch store.access {
        case .granted:
            for group in store.calendarsByAccount {
                let heading = NSMenuItem(title: group.account, action: nil, keyEquivalent: "")
                heading.isEnabled = false
                submenu.addItem(heading)
                for calendar in group.calendars {
                    let id = calendar.calendarIdentifier
                    let item = ActionItem(calendar.title, checked: !settings.hiddenCalendars.contains(id)) { [unowned self] in
                        if settings.hiddenCalendars.contains(id) {
                            settings.hiddenCalendars.remove(id)
                        } else {
                            settings.hiddenCalendars.insert(id)
                        }
                        store.reload()
                    }
                    item.image = swatch(calendar.color)
                    item.indentationLevel = 1
                    submenu.addItem(item)
                }
            }
            submenu.addItem(.separator())
        case .notDetermined:
            submenu.addItem(ActionItem("Allow Calendar Access…") { store.requestAccess() })
        case .denied:
            submenu.addItem(ActionItem("Open Privacy Settings…") { CalendarStore.openPrivacySettings() })
        }
        submenu.addItem(ActionItem("Add Google, Outlook or Other Account…") { CalendarStore.openInternetAccounts() })
        let item = NSMenuItem(title: "Calendars", action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func swatch(_ color: NSColor?) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            (color ?? NSColor.white.withAlphaComponent(0.35)).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 0.75
            path.stroke()
            return true
        }
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
