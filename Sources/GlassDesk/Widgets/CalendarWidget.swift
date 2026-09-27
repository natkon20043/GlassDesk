import AppKit
import EventKit
import SwiftUI

/// Today's date, a seven-day strip with event dots, and the next few events with
/// countdowns and one-click Join buttons for video calls.
struct CalendarWidget: View {
    private let store = CalendarStore.shared
    private let maxEvents = 5

    var body: some View {
        // Once a minute keeps countdowns fresh and drops events as they finish.
        TimelineView(.everyMinute) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 14) {
                header(now)
                WeekStrip(now: now, events: store.events)
                Group {
                    switch store.access {
                    case .granted: agenda(now)
                    case .notDetermined: accessPrompt
                    case .denied: deniedPrompt
                    }
                }
                // Fixed height keeps the widget's window from resizing as events come and go.
                .frame(height: 236, alignment: .top)
                .clipped()
            }
        }
    }

    // MARK: Header

    private func header(_ now: Date) -> some View {
        let todayCount = store.events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: now) && $0.endDate > now }.count
        return HStack(alignment: .center, spacing: 12) {
            Text(now.formatted(.dateTime.day()))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.rose)
            VStack(alignment: .leading, spacing: 0) {
                Text(now.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text(now.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.access == .granted {
                Text(todayCount == 0 ? "Free today" : "\(todayCount) left today")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: Agenda

    @ViewBuilder
    private func agenda(_ now: Date) -> some View {
        let upcoming = Array(store.events.filter { $0.endDate > now }.prefix(maxEvents))
        if upcoming.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(Palette.sun)
                Text("Nothing coming up this week")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Button("Add Google, Outlook or other account…", action: CalendarStore.openInternetAccounts)
                    .buttonStyle(.link)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(upcoming.enumerated()), id: \.offset) { index, event in
                    let isNewDay = index == 0 || !Calendar.current.isDate(event.startDate, inSameDayAs: upcoming[index - 1].startDate)
                    if isNewDay {
                        Text(dayLabel(for: event.startDate, now: now))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.top, index == 0 ? 0 : 2)
                    }
                    EventRow(event: event, now: now)
                }
            }
        }
    }

    private func dayLabel(for date: Date, now: Date) -> String {
        let calendar = Calendar.current
        // Multi-day events that started earlier are still "today".
        if date < now || calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: Permission states

    private var accessPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(Palette.rose)
            Text("See your events here")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text("Works with iCloud, Google, Outlook/Exchange and any calendar in the Calendar app.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Allow Calendar Access", action: store.requestAccess)
                .buttonStyle(.glassProminent)
                .tint(Palette.rose)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(Palette.orange)
            Text("Calendar access is off")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text("Turn on GlassDesk under Privacy & Security → Calendars, choosing \"Full Access\".")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Privacy Settings", action: CalendarStore.openPrivacySettings)
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Week strip

private struct WeekStrip: View {
    let now: Date
    let events: [EKEvent]

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        HStack(spacing: 0) {
            ForEach(0..<CalendarStore.lookaheadDays, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: today)!
                VStack(spacing: 4) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(day.formatted(.dateTime.day()))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 26, height: 26)
                        .background {
                            if offset == 0 { Circle().fill(Palette.rose) }
                        }
                    HStack(spacing: 2) {
                        ForEach(Array(dotColors(on: day).enumerated()), id: \.offset) { _, color in
                            Circle().fill(color).frame(width: 4, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// One dot per calendar with something on that day, at most three.
    private func dotColors(on day: Date) -> [Color] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        var seen = Set<String>()
        var colors: [Color] = []
        for event in events where event.startDate < end && event.endDate > day {
            guard let calendar = event.calendar, seen.insert(calendar.calendarIdentifier).inserted else { continue }
            colors.append(Color(nsColor: calendar.color))
            if colors.count == 3 { break }
        }
        return colors
    }
}

// MARK: - Event row

private struct EventRow: View {
    let event: EKEvent
    let now: Date

    private var color: Color { event.calendar.map { Color(nsColor: $0.color) } ?? Palette.sky }
    private var isOngoing: Bool { event.startDate <= now && event.endDate > now }

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(color)
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title?.isEmpty == false ? event.title! : "Untitled")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            trailing
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: openInCalendar)
        .help("Open in Calendar")
    }

    @ViewBuilder
    private var trailing: some View {
        let startsSoon = event.startDate.timeIntervalSince(now) < 15 * 60
        if !event.isAllDay, let link = meetingLink, isOngoing || startsSoon {
            Button {
                NSWorkspace.shared.open(link)
            } label: {
                Label("Join", systemImage: "video.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .buttonStyle(.glassProminent)
            .tint(color)
            .controlSize(.small)
        } else if let badge {
            Text(badge)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(isOngoing ? 0.45 : 0.22), in: Capsule())
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if event.isAllDay {
            parts.append("All day")
        } else {
            let start = event.startDate.formatted(date: .omitted, time: .shortened)
            let end = Calendar.current.isDate(event.endDate, inSameDayAs: event.startDate)
                ? event.endDate.formatted(date: .omitted, time: .shortened)
                : event.endDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            parts.append("\(start) – \(end)")
        }
        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty,
           !location.hasPrefix("http") {
            parts.append(location)
        }
        return parts.joined(separator: " · ")
    }

    /// "Now" for events in progress, a countdown for timed events later today.
    private var badge: String? {
        if isOngoing { return event.isAllDay ? nil : "Now" }
        guard Calendar.current.isDate(event.startDate, inSameDayAs: now) else { return nil }
        let minutes = Int((event.startDate.timeIntervalSince(now) / 60).rounded(.up))
        return minutes < 60 ? "in \(minutes)m" : "in \(minutes / 60)h"
    }

    /// Zoom, Google Meet, Teams or Webex link from the event's URL, location or notes.
    private var meetingLink: URL? {
        let pattern = #"https://[^\s<>"]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com)[^\s<>"]*"#
        for text in [event.url?.absoluteString, event.location, event.notes].compactMap({ $0 }) {
            if let range = text.range(of: pattern, options: .regularExpression) {
                return URL(string: String(text[range]))
            }
        }
        return nil
    }

    private func openInCalendar() {
        let identifier = event.calendarItemIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        if let url = URL(string: "ical://ekevent/\(identifier)?method=show&options=more") {
            NSWorkspace.shared.open(url)
        }
    }
}
