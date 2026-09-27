import AppKit
import EventKit
import Observation

/// Upcoming events from every calendar macOS knows about. EventKit reads the same database
/// as the Calendar app, so anything added under System Settings → Internet Accounts
/// (iCloud, Google, Exchange/Outlook, Yahoo, CalDAV) or subscribed to in Calendar
/// (File → New Calendar Subscription, for any .ics link) shows up here.
@MainActor
@Observable
final class CalendarStore {
    enum Access { case notDetermined, granted, denied }

    static let shared = CalendarStore()
    /// How far ahead the widget looks.
    static let lookaheadDays = 7

    private(set) var access: Access
    private(set) var events: [EKEvent] = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var timer: Timer?

    private init() {
        access = Self.currentAccess()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // Belt and braces for remote accounts; EKEventStoreChanged covers local edits.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.refreshSourcesIfNecessary()
                self?.reload()
            }
        }
        if access == .notDetermined {
            requestAccess()
        } else {
            reload()
        }
    }

    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.access = Self.currentAccess()
                    self.reload()
                }
            }
        }
    }

    func reload() {
        guard access == .granted else {
            events = []
            return
        }
        let hidden = Settings.shared.hiddenCalendars
        let calendars = store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            events = []
            return
        }
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: Self.lookaheadDays, to: start)!
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        events = store.events(matching: predicate)
            .sorted { $0.compareStartDate(with: $1) == .orderedAscending }
    }

    /// Every event calendar, grouped by account ("iCloud", "you@gmail.com", …) for the menu.
    var calendarsByAccount: [(account: String, calendars: [EKCalendar])] {
        guard access == .granted else { return [] }
        let grouped = Dictionary(grouping: store.calendars(for: .event)) { $0.source.title }
        return grouped
            .map { (account: $0.key, calendars: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.account < $1.account }
    }

    static func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    static func openInternetAccounts() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied  // denied, restricted, or write-only (which can't read events)
        }
    }
}
