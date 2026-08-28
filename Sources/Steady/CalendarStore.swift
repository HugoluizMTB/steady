import Foundation
import EventKit

struct CalendarAccount: Identifiable, Hashable {
    let id: String
    let name: String
    let type: String
    let calendarCount: Int
}

struct WritableCalendar: Identifiable, Hashable {
    let id: String
    let title: String
    let colorHex: String
    let account: String
}

struct CalendarEntry: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let calendar: String
    let colorHex: String
    let location: String
    let meetingURL: String?
}

@MainActor
final class CalendarStore: ObservableObject {
    enum Access { case unknown, granted, denied }

    private let store = EKEventStore()
    @Published private(set) var access: Access = .unknown
    @Published private(set) var accounts: [CalendarAccount] = []
    @Published private(set) var writableCalendars: [WritableCalendar] = []
    @Published private(set) var entries: [CalendarEntry] = []
    @Published private(set) var monthEntries: [CalendarEntry] = []
    @Published private(set) var month: Date = Date()
    @Published private(set) var loading = false

    init() {
        month = startOfMonth(Date())
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted; loadAll()
        case .denied, .restricted: access = .denied
        default: access = .unknown
        }
    }

    func connect() {
        loading = true
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
            if granted { loadAll() } else { loading = false }
        }
    }

    func refresh() {
        if access == .granted { loadAll() }
    }

    func showMonth(offset: Int) {
        guard let next = Calendar.current.date(byAdding: .month, value: offset, to: month) else { return }
        month = startOfMonth(next)
        loadMonth()
    }

    @discardableResult
    func addEvent(title: String, calendarID: String, start: Date, end: Date, allDay: Bool) -> Bool {
        guard let calendar = store.calendar(withIdentifier: calendarID) else { return false }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = calendar
        event.isAllDay = allDay
        event.startDate = start
        event.endDate = allDay ? start : max(end, start.addingTimeInterval(900))
        do {
            try store.save(event, span: .thisEvent, commit: true)
            loadAll()
            return true
        } catch {
            return false
        }
    }

    private func loadAll() {
        loading = true
        let calendars = store.calendars(for: .event)

        var grouped: [String: (name: String, type: String, count: Int)] = [:]
        for calendar in calendars {
            guard let source = calendar.source else { continue }
            let existing = grouped[source.sourceIdentifier]
            grouped[source.sourceIdentifier] = (source.title, sourceLabel(source.sourceType), (existing?.count ?? 0) + 1)
        }
        accounts = grouped
            .map { CalendarAccount(id: $0.key, name: $0.value.name, type: $0.value.type, calendarCount: $0.value.count) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        writableCalendars = calendars
            .filter { $0.allowsContentModifications }
            .map { WritableCalendar(id: $0.calendarIdentifier, title: $0.title, colorHex: hex(from: $0.cgColor), account: $0.source?.title ?? "") }

        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start
        entries = events(from: start, to: end, calendars: calendars).prefix(120).map { $0 }

        loadMonth(calendars: calendars)
        loading = false
    }

    private func loadMonth(calendars: [EKCalendar]? = nil) {
        let calendars = calendars ?? store.calendars(for: .event)
        let start = month
        guard let end = Calendar.current.date(byAdding: .month, value: 1, to: start) else { return }
        monthEntries = events(from: start, to: end, calendars: calendars)
    }

    private func events(from start: Date, to end: Date, calendars: [EKCalendar]) -> [CalendarEntry] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .map { entry(from: $0) }
    }

    private func entry(from event: EKEvent) -> CalendarEntry {
        CalendarEntry(
            id: (event.eventIdentifier ?? "") + event.startDate.description,
            title: event.title ?? "(No title)",
            start: event.startDate,
            end: event.endDate,
            allDay: event.isAllDay,
            calendar: event.calendar.title,
            colorHex: hex(from: event.calendar.cgColor),
            location: event.location ?? "",
            meetingURL: meetingURL(for: event)
        )
    }

    private func meetingURL(for event: EKEvent) -> String? {
        let candidates = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        let patterns = [
            "https://meet\\.google\\.com/[a-zA-Z0-9-]+",
            "https://[a-zA-Z0-9.]*zoom\\.us/j/[0-9]+[^\\s\"<]*",
            "https://teams\\.microsoft\\.com/l/meetup-join/[^\\s\"<]+",
            "https://[a-zA-Z0-9.]*webex\\.com/[^\\s\"<]+"
        ]
        for text in candidates {
            for pattern in patterns {
                if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    return String(text[range])
                }
            }
        }
        return nil
    }

    private func startOfMonth(_ date: Date) -> Date {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: components) ?? date
    }

    private func sourceLabel(_ type: EKSourceType) -> String {
        switch type {
        case .local: return "On My Mac"
        case .calDAV: return "CalDAV"
        case .exchange: return "Exchange"
        case .subscribed: return "Subscribed"
        case .birthdays: return "Birthdays"
        @unknown default: return "Account"
        }
    }

    private func hex(from cgColor: CGColor?) -> String {
        guard let components = cgColor?.components, components.count >= 3 else { return "8ee7bd" }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        return String(format: "%02x%02x%02x", r, g, b)
    }
}
