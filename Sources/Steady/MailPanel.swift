import SwiftUI
import AppKit

struct MailPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void

    private let store = SteadyStores.shared.mail
    @State private var showingCompose = false
    @State private var showingFilter = false

    private var context: SteadyContext { SteadyData.context("gmail") ?? SteadyData.contexts[0] }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: context, title: "Mail", subtitle: subtitle, onSnooze: onSnooze, onResolve: onResolve)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            content
        }
        .sheet(isPresented: $showingCompose) {
            MailComposeSheet(store: store) { showingCompose = false }
        }
        .sheet(item: Binding(get: { store.openMessage }, set: { if $0 == nil { store.closeOpen() } })) { message in
            MailMessageView(store: store, message: message)
        }
    }

    private var subtitle: String {
        switch store.access {
        case .unknown: return "Read the mail already on this Mac"
        case .denied: return "Automation access is off"
        case .granted:
            let account = store.accounts.first ?? ""
            return "\(store.unreadCount) unread\(account.isEmpty ? "" : "  ·  \(account)")"
        }
    }

    @ViewBuilder private var content: some View {
        switch store.access {
        case .unknown: MailConnectView(onConnect: store.connect)
        case .denied: MailDeniedView()
        case .granted: granted
        }
    }

    private var granted: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            if store.visibleMessages.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.visibleMessages) { message in
                            MailMessageRow(message: message) { store.open(message) }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button { showingFilter = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: store.mutedSenders.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    Text(store.mutedSenders.isEmpty ? "Filter" : "\(store.mutedSenders.count) hidden")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(store.mutedSenders.isEmpty ? SteadyPalette.muted : SteadyPalette.mint)
                .padding(.horizontal, 10).frame(height: 30)
                .overlay(Capsule().stroke(SteadyPalette.line))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingFilter, arrowEdge: .bottom) {
                MailSenderFilter(store: store).frame(width: 300, height: 360)
            }

            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SteadyPalette.muted).frame(width: 30, height: 30)
                    .overlay(Circle().stroke(SteadyPalette.line))
            }
            .buttonStyle(.plain)
            .disabled(store.loading)

            Spacer()

            Button { showingCompose = true } label: {
                Label("New", systemImage: "square.and.pencil").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "102019")).padding(.horizontal, 12).frame(height: 30)
                    .background(Capsule().fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if store.loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "tray").font(.system(size: 26)).foregroundStyle(SteadyPalette.muted)
                Text(store.mutedSenders.isEmpty ? "Inbox is empty." : "Every sender is filtered out.")
                    .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
                if !store.mutedSenders.isEmpty {
                    Button("Show all") { store.showAll() }
                        .buttonStyle(.plain).foregroundStyle(SteadyPalette.mint).font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MailMessageRow: View {
    let message: MailMessage
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Circle().fill(message.unread ? SteadyPalette.mint : Color.clear)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(message.unread ? Color.clear : SteadyPalette.lineStrong))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(message.senderName)
                            .font(.system(size: 13, weight: message.unread ? .semibold : .medium))
                            .foregroundStyle(SteadyPalette.ink).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(message.dateText).font(.system(size: 10)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                    }
                    Text(message.subject)
                        .font(.system(size: 12))
                        .foregroundStyle(message.unread ? Color(hex: "c8cbd0") : SteadyPalette.muted).lineLimit(1)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: "16191d").opacity(message.unread ? 0.85 : 0.5)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(SteadyPalette.line))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

private struct MailConnectView: View {
    let onConnect: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "envelope").font(.system(size: 30)).foregroundStyle(SteadyPalette.muted)
            Text("Connect Mail").font(.system(size: 15, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
            Text("Steady reads the inbox from the Mail app already set up on this Mac. No new login — macOS will ask to allow automation once.")
                .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted).multilineTextAlignment(.center).frame(maxWidth: 340)
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

private struct MailDeniedView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope.badge.shield.half.filled").font(.system(size: 28)).foregroundStyle(SteadyPalette.muted)
            Text("Automation access is off").font(.system(size: 14, weight: .medium)).foregroundStyle(SteadyPalette.ink)
            Text("Enable it in System Settings → Privacy & Security → Automation → Steady → Mail.")
                .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted).multilineTextAlignment(.center).frame(maxWidth: 340)
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
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }
}
