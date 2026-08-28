import SwiftUI
import AppKit

struct CalendarPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void

    @StateObject private var store = CalendarStore()
    @State private var mode: Mode = .agenda
    @State private var selectedDay = Date()
    @State private var showingAdd = false

    enum Mode { case agenda, month }

    private var context: SteadyContext { SteadyData.context("calendar") ?? SteadyData.contexts[0] }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: context, title: "Calendar", subtitle: subtitle, onSnooze: onSnooze, onResolve: onResolve)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            content
        }
        .sheet(isPresented: $showingAdd) {
            AddEventSheet(store: store) { showingAdd = false }
        }
    }

    private var subtitle: String {
        switch store.access {
        case .unknown: return "Connect the calendars already on this Mac"
        case .denied: return "Calendar access is off"
        case .granted:
            let count = store.accounts.count
            return "\(store.entries.count) upcoming  ·  \(count) account\(count == 1 ? "" : "s")"
        }
    }

    @ViewBuilder private var content: some View {
        switch store.access {
        case .unknown: CalendarConnectView(onConnect: store.connect)
        case .denied: CalendarDeniedView()
        case .granted: grantedView
        }
    }

    private var grantedView: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            switch mode {
            case .agenda: CalendarAgendaView(accounts: store.accounts, entries: store.entries)
            case .month: CalendarMonthView(store: store, selectedDay: $selectedDay)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                segment("Agenda", .agenda)
                segment("Month", .month)
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
            Spacer()
            Button { showingAdd = true } label: {
                Label("New event", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "102019")).padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
            .disabled(store.writableCalendars.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }

    private func segment(_ title: String, _ value: Mode) -> some View {
        Button { mode = value } label: {
            Text(title).font(.system(size: 12, weight: .medium))
                .foregroundStyle(mode == value ? SteadyPalette.ink : SteadyPalette.muted)
                .padding(.horizontal, 12).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(mode == value ? Color.white.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
    }
}

private struct CalendarConnectView: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar").font(.system(size: 30)).foregroundStyle(SteadyPalette.muted)
            Text("Connect your calendars").font(.system(size: 15, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
            Text("Steady reads every calendar account already set up on this Mac — iCloud, Google, Exchange. No new login.")
                .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted).multilineTextAlignment(.center).frame(maxWidth: 320)
            Button(action: onConnect) {
                Label("Connect", systemImage: "link").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "102019")).padding(.horizontal, 18).frame(height: 34)
                    .background(Capsule().fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct CalendarDeniedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 28)).foregroundStyle(SteadyPalette.muted)
            Text("Calendar access is off").font(.system(size: 14, weight: .medium)).foregroundStyle(SteadyPalette.ink)
            Text("Enable it in System Settings → Privacy & Security → Calendars → Steady.")
                .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted).multilineTextAlignment(.center).frame(maxWidth: 320)
            Button(action: openSettings) {
                Text("Open Settings").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 30).background(Capsule().fill(Color.white.opacity(0.08)))
                    .overlay(Capsule().stroke(SteadyPalette.line))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") else { return }
        NSWorkspace.shared.open(url)
    }
}
