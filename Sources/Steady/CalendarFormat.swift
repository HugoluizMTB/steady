import Foundation

enum CalendarFormat {
    static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        return formatted(date, "EEEE, MMM d")
    }

    static func shortTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    static func monthTitle(_ date: Date) -> String {
        formatted(date, "MMMM yyyy")
    }

    static var weekdaySymbols: [String] {
        DateFormatter().veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
    }

    static func groupedByDay(_ items: [CalendarEntry]) -> [(day: Date, entries: [CalendarEntry])] {
        Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.start) }
            .sorted { $0.key < $1.key }
            .map { (day: $0.key, entries: $0.value) }
    }

    static func eventsByDay(_ items: [CalendarEntry]) -> [Date: [CalendarEntry]] {
        Dictionary(grouping: items) { Calendar.current.startOfDay(for: $0.start) }
    }

    static func monthGridDays(of month: Date) -> [Date] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let leading = calendar.component(.weekday, from: month) - 1
        var days: [Date] = []
        for offset in stride(from: leading, to: 0, by: -1) {
            if let date = calendar.date(byAdding: .day, value: -offset, to: month) { days.append(date) }
        }
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: month) { days.append(date) }
        }
        while days.count % 7 != 0, let last = days.last, let next = calendar.date(byAdding: .day, value: 1, to: last) {
            days.append(next)
        }
        return days
    }

    private static func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
