import SwiftUI

struct MailSenderFilter: View {
    let store: MailStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Senders").font(.system(size: 13, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
                Spacer()
                Button("Show all") { store.showAll() }
                    .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.mutedSenders.isEmpty ? SteadyPalette.muted : SteadyPalette.mint)
                    .disabled(store.mutedSenders.isEmpty)
            }
            .padding(12)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(store.senders) { sender in
                        SenderRow(sender: sender, shown: !store.mutedSenders.contains(sender.email)) {
                            store.toggleMute(sender.email)
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(SteadyPalette.canvas)
    }
}

private struct SenderRow: View {
    let sender: SenderSummary
    let shown: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 9) {
                Image(systemName: shown ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14)).foregroundStyle(shown ? SteadyPalette.mint : SteadyPalette.muted)
                VStack(alignment: .leading, spacing: 1) {
                    Text(sender.name).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(shown ? SteadyPalette.ink : SteadyPalette.muted).lineLimit(1)
                    Text(sender.email).font(.system(size: 10)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text("\(sender.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(SteadyPalette.muted)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.02)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
