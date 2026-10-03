import AppKit
import EventKit

/// A mode for taking the photos in the README. With `GLASSDESK_DEMO=1` the widgets show made-up
/// data instead of the person's own: a neutral name, sample calendar events, a synthetic sound
/// spectrum and a sprite from a separate folder. Nothing personal is read, and nothing is saved
/// anywhere the real app looks.
enum DemoMode {
    static let isOn = ProcessInfo.processInfo.environment["GLASSDESK_DEMO"] != nil

    static let firstName = "Sam"

    /// Where the demo sprite lives (the real one is in Application Support).
    static var spriteFolder: URL? {
        guard isOn else { return nil }
        let base = ProcessInfo.processInfo.environment["GLASSDESK_DEMO_FOLDER"] ?? NSTemporaryDirectory() + "glassdesk-demo"
        return URL(fileURLWithPath: base).appending(path: "Sprite")
    }

    /// A week of plausible events, starting from now: two calendars, an all-day event, one about to start.
    @MainActor
    static func sampleEvents(in store: EKEventStore) -> [EKEvent] {
        let work = EKCalendar(for: .event, eventStore: store)
        work.title = "Work"
        work.cgColor = NSColor(srgbRed: 0.36, green: 0.55, blue: 1.0, alpha: 1).cgColor
        let home = EKCalendar(for: .event, eventStore: store)
        home.title = "Home"
        home.cgColor = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.25, alpha: 1).cgColor

        let calendar = Calendar.current
        let now = Date()
        let midnight = calendar.startOfDay(for: now)

        func event(_ title: String, calendar owner: EKCalendar, start: Date, minutes: Int, location: String? = nil, allDay: Bool = false) -> EKEvent {
            let event = EKEvent(eventStore: store)
            event.title = title
            event.calendar = owner
            event.startDate = start
            event.endDate = allDay ? start : start.addingTimeInterval(TimeInterval(minutes * 60))
            event.isAllDay = allDay
            event.location = location
            return event
        }
        func day(_ offset: Int, hour: Int, minute: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: offset, to: midnight)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
        }

        return [
            event("Design review", calendar: work, start: now.addingTimeInterval(25 * 60), minutes: 30, location: "Studio B"),
            event("Lunch with Alex", calendar: home, start: now.addingTimeInterval(2 * 3600), minutes: 60, location: "Corner Café"),
            event("Focus time", calendar: work, start: now.addingTimeInterval(4 * 3600), minutes: 90),
            event("Weekly planning", calendar: work, start: day(1, hour: 9, minute: 30), minutes: 45),
            event("Dentist", calendar: home, start: day(1, hour: 14), minutes: 45, location: "Main Street Dental"),
            event("Sam's birthday", calendar: home, start: day(2, hour: 0), minutes: 0, allDay: true),
            event("Release day", calendar: work, start: day(3, hour: 11), minutes: 60),
            event("Pottery class", calendar: home, start: day(4, hour: 18, minute: 30), minutes: 120, location: "The Studio"),
        ]
    }
}
