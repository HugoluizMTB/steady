import SwiftUI
import AppKit

struct EventRow: View {
    let entry: CalendarEntry

    var body: some View {
        HStack(spacing: 11) {
            Circle().fill(Color(hex: entry.colorHex)).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.system(size: 13, weight: .medium)).foregroundStyle(SteadyPalette.ink).lineLimit(1)
                HStack(spacing: 6) {
                    Text(timeLabel).font(.system(size: 11)).foregroundStyle(Color(hex: "a9acb1"))
                    Text("·").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
                    Text(entry.calendar).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let meeting = entry.meetingURL, let url = URL(string: meeting) {
                JoinButton(url: url)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: "16191d").opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(SteadyPalette.line))
    }

    private var timeLabel: String {
        entry.allDay ? "All day" : CalendarFormat.shortTime(entry.start)
    }
}

private struct JoinButton: View {
    let url: URL

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Label("Join", systemImage: "video.fill").font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: "102019")).padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(SteadyPalette.mint))
        }
        .buttonStyle(.plain)
    }
}
