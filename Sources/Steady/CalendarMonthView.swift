import SwiftUI

struct CalendarMonthView: View {
    @ObservedObject var store: CalendarStore
    @Binding var selectedDay: Date

    private var eventsByDay: [Date: [CalendarEntry]] { CalendarFormat.eventsByDay(store.monthEntries) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                monthNav
                weekdayHeader
                grid
                SelectedDaySection(day: selectedDay, entries: events(on: selectedDay))
            }
            .padding(20)
        }
    }

    private var monthNav: some View {
        HStack(spacing: 14) {
            navButton("chevron.left") { store.showMonth(offset: -1) }
            Text(CalendarFormat.monthTitle(store.month))
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
            navButton("chevron.right") { store.showMonth(offset: 1) }
            Spacer()
        }
    }

    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.plain).foregroundStyle(SteadyPalette.muted)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(CalendarFormat.weekdaySymbols, id: \.self) { symbol in
                Text(symbol).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(SteadyPalette.muted).frame(maxWidth: .infinity)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(CalendarFormat.monthGridDays(of: store.month), id: \.self) { day in
                MonthDayCard(
                    date: day,
                    inMonth: Calendar.current.isDate(day, equalTo: store.month, toGranularity: .month),
                    isToday: Calendar.current.isDateInToday(day),
                    selected: Calendar.current.isDate(day, inSameDayAs: selectedDay),
                    events: events(on: day)
                ) { selectedDay = day }
            }
        }
    }

    private func events(on day: Date) -> [CalendarEntry] {
        eventsByDay[Calendar.current.startOfDay(for: day)] ?? []
    }
}

private struct SelectedDaySection: View {
    let day: Date
    let entries: [CalendarEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CalendarFormat.dayLabel(Calendar.current.startOfDay(for: day)))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "b6b9be"))
            if entries.isEmpty {
                Text("No events.").font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
            } else {
                ForEach(entries) { EventRow(entry: $0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
    }
}

struct MonthDayCard: View {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let selected: Bool
    let events: [CalendarEntry]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.system(size: 11, weight: isToday ? .bold : .medium))
                    .foregroundStyle(dayColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(events.prefix(3)) { EventChip(entry: $0) }
                if events.count > 3 {
                    Text("+\(events.count - 3)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(SteadyPalette.muted).padding(.leading, 3)
                }
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var dayColor: Color {
        if !inMonth { return Color(hex: "3f4348") }
        return isToday ? SteadyPalette.mint : SteadyPalette.ink
    }

    private var fill: Color {
        if selected { return Color.white.opacity(0.09) }
        if isToday { return SteadyPalette.mint.opacity(0.10) }
        return Color(hex: "16191d").opacity(inMonth ? 0.72 : 0.30)
    }

    private var stroke: Color {
        if selected { return SteadyPalette.mint.opacity(0.5) }
        if isToday { return SteadyPalette.mint.opacity(0.3) }
        return SteadyPalette.line
    }
}

struct EventChip: View {
    let entry: CalendarEntry

    var body: some View {
        HStack(spacing: 4) {
            if entry.allDay {
                Circle().fill(Color(hex: entry.colorHex)).frame(width: 5, height: 5)
            } else {
                Text(CalendarFormat.shortTime(entry.start))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(hex: entry.colorHex)).monospacedDigit()
            }
            Text(entry.title).font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color(hex: "e6e8ea")).lineLimit(1)
        }
        .padding(.horizontal, 5).padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: entry.colorHex).opacity(0.20)))
    }
}
