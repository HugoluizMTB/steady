import SwiftUI

struct AddEventSheet: View {
    let store: CalendarStore
    let onClose: () -> Void

    @State private var title = ""
    @State private var calendarID = ""
    @State private var day = Date()
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var allDay = false

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !calendarID.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            fields
            Spacer()
        }
        .frame(width: 360, height: allDay ? 300 : 380)
        .background(SteadyPalette.canvas)
        .onAppear { if calendarID.isEmpty { calendarID = store.writableCalendars.first?.id ?? "" } }
    }

    private var header: some View {
        HStack {
            Button("Cancel", action: onClose).buttonStyle(.plain).foregroundStyle(SteadyPalette.muted)
            Spacer()
            Text("New event").font(.system(size: 13, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
            Spacer()
            Button("Add") { save() }
                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canSave ? SteadyPalette.mint : SteadyPalette.muted)
                .disabled(!canSave)
        }
        .padding(14)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            Picker("Calendar", selection: $calendarID) {
                ForEach(store.writableCalendars) { calendar in
                    Text("\(calendar.title)  ·  \(calendar.account)").tag(calendar.id)
                }
            }
            Toggle("All day", isOn: $allDay)
            DatePicker("Date", selection: $day, displayedComponents: .date)
            if !allDay {
                DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
            }
        }
        .padding(16)
    }

    private func save() {
        let startDate = combine(day: day, time: start)
        let endDate = combine(day: day, time: end)
        if store.addEvent(title: title.trimmingCharacters(in: .whitespaces), calendarID: calendarID, start: startDate, end: endDate, allDay: allDay) {
            onClose()
        }
    }

    private func combine(day: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: day)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = dayComponents.year
        merged.month = dayComponents.month
        merged.day = dayComponents.day
        merged.hour = allDay ? 0 : timeComponents.hour
        merged.minute = allDay ? 0 : timeComponents.minute
        return calendar.date(from: merged) ?? day
    }
}
