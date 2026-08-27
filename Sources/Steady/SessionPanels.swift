import SwiftUI

private let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()

func relativeTime(_ date: Date) -> String {
    relativeFormatter.localizedString(for: date, relativeTo: Date())
}

func shortTokens(_ count: Int) -> String {
    if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
    if count >= 1_000 { return String(format: "%.0fk", Double(count) / 1_000) }
    return "\(count)"
}

private func rank(_ state: AgentSession.State) -> Int {
    switch state { case .waiting: return 0; case .working: return 1; case .idle: return 2 }
}

private struct SessionGroup: Identifiable {
    let id: String
    let project: String
    let sessions: [AgentSession]
}

struct ClaudeSessionsPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void
    private let store = SteadyStores.shared.sessions
    private var context: SteadyContext { SteadyData.context("claude")! }

    var body: some View {
        SessionInbox(context: context, name: "Claude Code", sessions: store.claude, loading: store.loading,
                     onSnooze: onSnooze, onResolve: onResolve)
    }
}

struct CodexSessionsPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void
    private let store = SteadyStores.shared.sessions
    private var context: SteadyContext { SteadyData.context("codex")! }

    var body: some View {
        SessionInbox(context: context, name: "Codex", sessions: store.codex, loading: store.loading,
                     onSnooze: onSnooze, onResolve: onResolve)
    }
}

private struct SessionInbox: View {
    let context: SteadyContext
    let name: String
    let sessions: [AgentSession]
    let loading: Bool
    let onSnooze: () -> Void
    let onResolve: () -> Void

    private let store = SteadyStores.shared.sessions
    @State private var openSession: AgentSession?

    private var grouped: [SessionGroup] {
        Dictionary(grouping: sessions, by: { $0.project })
            .map { key, value in
                SessionGroup(id: key, project: key, sessions: value.sorted { a, b in
                    let pa = store.isPinned(a), pb = store.isPinned(b)
                    if pa != pb { return pa }
                    return rank(a.state) != rank(b.state) ? rank(a.state) < rank(b.state) : a.modified > b.modified
                })
            }
            .sorted { lhs, rhs in
                let lp = lhs.sessions.contains { store.isPinned($0) }
                let rp = rhs.sessions.contains { store.isPinned($0) }
                if lp != rp { return lp }
                return lhs.project.lowercased() < rhs.project.lowercased()
            }
    }

    var body: some View {
        if let session = openSession {
            SessionTerminalPanel(context: context, session: session,
                                 onBack: { openSession = nil }, onSnooze: onSnooze, onResolve: onResolve)
        } else {
            VStack(spacing: 0) {
                PanelHeader(context: context, title: name, subtitle: subtitle,
                            onSnooze: onSnooze, onResolve: onResolve)
                Rectangle().fill(SteadyPalette.line).frame(height: 1)
                if sessions.isEmpty {
                    VStack(spacing: 10) {
                        if loading { ProgressView().controlSize(.small) }
                        Image(systemName: "moon.zzz").font(.system(size: 22)).foregroundStyle(SteadyPalette.muted)
                        Text(loading ? "Looking for live sessions…" : "No open \(name) sessions")
                            .font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(grouped) { entry in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
                                        Text(entry.project).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "c9cbd0"))
                                        Text("\(entry.sessions.count)").font(.system(size: 11)).foregroundStyle(Color(hex: "5c5f66"))
                                    }
                                    ForEach(entry.sessions) { session in
                                        SessionCard(session: session) { openSession = session }
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
    }

    private var subtitle: String {
        if loading && sessions.isEmpty { return "Looking for live sessions…" }
        let waiting = sessions.filter { $0.state == .waiting }.count
        return waiting > 0 ? "\(waiting) waiting  ·  \(sessions.count) open" : "\(sessions.count) open"
    }
}

private struct SessionCard: View {
    let session: AgentSession
    let onOpen: () -> Void
    private let store = SteadyStores.shared.sessions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(session.activity)
                .font(.system(size: 13))
                .foregroundStyle(session.state == .waiting ? Color(hex: "dcdee1") : Color(hex: "9a9da3"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            statusline
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "16191d").opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(session.state == .waiting ? SteadyPalette.mint.opacity(0.28) : SteadyPalette.line))
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .contextMenu {
            Button("Rename…") { store.rename(session) }
            Button(store.isPinned(session) ? "Unpin" : "Pin") { store.togglePin(session) }
            Divider()
            Button("Open in Terminal") { store.openInTerminal(session) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.state == .waiting ? SteadyPalette.mint : (session.state == .working ? Color.orange : Color(hex: "5c5f66")))
                .frame(width: 9, height: 9)
            if store.isPinned(session) {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(SteadyPalette.mint)
            }
            Text(store.title(for: session)).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SteadyPalette.ink).lineLimit(1)
            Spacer(minLength: 6)
            statusLabel
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch session.state {
        case .waiting:
            Text("Waiting for you").font(.system(size: 11, weight: .semibold)).foregroundStyle(SteadyPalette.mint)
        case .working:
            HStack(spacing: 6) {
                TypingDots()
                Text("Working").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.orange)
            }
        case .idle:
            Text("Idle \(relativeTime(session.modified))").font(.system(size: 11)).foregroundStyle(Color(hex: "6b6e74"))
        }
    }

    private var statusline: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                if !session.shortModel.isEmpty { Text(session.shortModel) }
                if session.contextTokens > 0 { separator; Text("\(shortTokens(session.contextTokens)) ctx") }
                if !session.branch.isEmpty { separator; Image(systemName: "arrow.triangle.branch").font(.system(size: 9)); Text(session.branch) }
                if session.worktree { separator; Text("worktree") }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(hex: "8b8e95"))
            .lineLimit(1)
            Spacer(minLength: 6)
            if let number = session.prNumber {
                Button { store.openPR(session) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.pull").font(.system(size: 10))
                        Text("#\(number)").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "6f76ff"))
                }
                .buttonStyle(.plain)
            }
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
        }
    }

    private var separator: some View { Text("·").foregroundStyle(Color(hex: "45484d")) }
}

private struct SessionTerminalPanel: View {
    let context: SteadyContext
    let session: AgentSession
    let onBack: () -> Void
    let onSnooze: () -> Void
    let onResolve: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                BrandIcon(context: context, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SteadyStores.shared.sessions.title(for: session)).font(.system(size: 15, weight: .semibold)).foregroundStyle(SteadyPalette.ink).lineLimit(1)
                    Text("\(session.project)\(session.branch.isEmpty ? "" : "  ·  " + session.branch)  ·  live")
                        .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                }
                Spacer()
                PanelActions(onSnooze: onSnooze, onResolve: onResolve)
            }
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 14, trailing: 20))
            Rectangle().fill(SteadyPalette.line).frame(height: 1)

            SessionTerminal(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(hex: "080a0c"))
        }
    }
}

struct TypingDots: View {
    @State private var phase = 0.0
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(Color.orange)
                    .frame(width: 4, height: 4)
                    .opacity(0.35 + 0.65 * max(0, sin(phase - Double(index) * 0.6)))
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
    }
}
