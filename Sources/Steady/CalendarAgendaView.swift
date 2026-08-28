import SwiftUI

struct CalendarAgendaView: View {
    let accounts: [CalendarAccount]
    let entries: [CalendarEntry]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !accounts.isEmpty { accountChips }
                if entries.isEmpty {
                    Text("Nothing in the next 14 days.")
                        .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted).padding(.top, 6)
                } else {
                    ForEach(CalendarFormat.groupedByDay(entries), id: \.day) { group in
                        DaySection(day: group.day, entries: group.entries)
                    }
                }
            }
            .padding(20)
        }
    }

    private var accountChips: some View {
        HStack(spacing: 8) {
            ForEach(accounts) { AccountChip(account: $0) }
            Spacer(minLength: 0)
        }
    }
}

private struct DaySection: View {
    let day: Date
    let entries: [CalendarEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CalendarFormat.dayLabel(day))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "b6b9be"))
            ForEach(entries) { EventRow(entry: $0) }
        }
    }
}

private struct AccountChip: View {
    let account: CalendarAccount

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "person.crop.circle").font(.system(size: 10)).foregroundStyle(SteadyPalette.muted)
            Text(account.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: "d4d6da"))
            Text("\(account.calendarCount)").font(.system(size: 10)).foregroundStyle(SteadyPalette.muted)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .overlay(Capsule().stroke(SteadyPalette.line))
    }
}
