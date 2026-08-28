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

struct ClaudeSessionsPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void
    private let store = SteadyStores.shared.sessions
    private var context: SteadyContext { SteadyData.context("claude")! }

    var body: some View {
        SessionInbox(context: context, kind: .claude, name: "Claude Code", sessions: store.claude,
                     loading: store.loading, onSnooze: onSnooze, onResolve: onResolve)
    }
}

struct CodexSessionsPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void
    private let store = SteadyStores.shared.sessions
    private var context: SteadyContext { SteadyData.context("codex")! }

    var body: some View {
        SessionInbox(context: context, kind: .codex, name: "Codex", sessions: store.codex,
                     loading: store.loading, onSnooze: onSnooze, onResolve: onResolve)
    }
}

private struct SessionInbox: View {
    let context: SteadyContext
    let kind: AgentSession.Kind
    let name: String
    let sessions: [AgentSession]
    let loading: Bool
    let onSnooze: () -> Void
    let onResolve: () -> Void

    private let store = SteadyStores.shared.sessions
    @State private var openSession: AgentSession?

    private var profiles: [AgentProfile] { store.profiles(for: kind) }

    private func sessions(in state: AgentSession.State) -> [AgentSession] {
        sessions.filter { $0.state == state }.sorted { lhs, rhs in
            let leftPinned = store.isPinned(lhs)
            let rightPinned = store.isPinned(rhs)
            if leftPinned != rightPinned { return leftPinned }
            return lhs.modified > rhs.modified
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
                boardToolbar
                Rectangle().fill(SteadyPalette.line).frame(height: 1)
                board
            }
        }
    }

    private var boardToolbar: some View {
        HStack(spacing: 10) {
            Label("Session board", systemImage: "rectangle.3.group")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: "b6b9be"))

            if profiles.count > 1 {
                Text("\(profiles.count) profiles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(SteadyPalette.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(Capsule().stroke(SteadyPalette.line))
            }

            Spacer()

            Menu {
                ForEach(profiles) { profile in
                    Button(profile.label) { store.startNewSession(kind: kind, profile: profile) }
                }
            } label: {
                Label("New session", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "102019"))
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Capsule().fill(SteadyPalette.mint))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Button { store.load() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SteadyPalette.muted)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(SteadyPalette.line))
            }
            .buttonStyle(.plain)
            .help("Refresh sessions")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var board: some View {
        if sessions.isEmpty {
            VStack(spacing: 12) {
                if loading { ProgressView().controlSize(.small) }
                Image(systemName: "rectangle.stack.badge.play")
                    .font(.system(size: 24))
                    .foregroundStyle(SteadyPalette.muted)
                Text(loading ? "Looking for live sessions…" : "No open \(name) sessions")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SteadyPalette.muted)
                Text("Start one in any folder, using the profile you choose.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "6f7278"))
                Menu {
                    ForEach(profiles) { profile in
                        Button("New with \(profile.label)") { store.startNewSession(kind: kind, profile: profile) }
                    }
                } label: {
                    Label("New session", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "102019"))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(Capsule().fill(SteadyPalette.mint))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 14) {
                SessionColumn(title: "Rodando", accent: false, sessions: sessions(in: .running), onOpen: { openSession = $0 })
                SessionColumn(title: "Concluídas", accent: true, sessions: sessions(in: .done), onOpen: { openSession = $0 })
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var subtitle: String {
        if loading && sessions.isEmpty { return "Looking for live sessions…" }
        let running = sessions.filter { $0.state == .running }.count
        var values: [String] = []
        if running > 0 { values.append("\(running) rodando") }
        values.append("\(sessions.count) open")
        if profiles.count > 1 { values.append("\(profiles.count) profiles") }
        return values.joined(separator: "  ·  ")
    }
}

private struct SessionColumn: View {
    let title: String
    let accent: Bool
    let sessions: [AgentSession]
    let onOpen: (AgentSession) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if accent { Circle().fill(SteadyPalette.mint).frame(width: 7, height: 7) }
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent ? SteadyPalette.mint : Color(hex: "b6b9be"))
                Text("\(sessions.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SteadyPalette.muted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            if sessions.isEmpty {
                Text("Nothing here")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "5c5f66"))
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 10) {
                        ForEach(sessions) { session in
                            SessionCard(session: session, onOpen: { onOpen(session) })
                        }
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SessionCard: View {
    let session: AgentSession
    let onOpen: () -> Void

    private let store = SteadyStores.shared.sessions
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header

            Text(session.activity)
                .font(.system(size: 13))
                .foregroundStyle(session.state == .done ? Color(hex: "eef5f1") : Color(hex: "a9acb1"))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            details
        }
        .padding(14)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture { if !editing { onOpen() } }
        .onHover { hovering = $0 }
        .contextMenu { sessionMenu }
    }

    private func beginEditing() {
        draft = store.title(for: session)
        editing = true
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitName() {
        store.setName(draft, for: session)
        editing = false
    }

    private var header: some View {
        HStack(spacing: 9) {
            Circle().fill(stateColor).frame(width: 9, height: 9)

            if store.isPinned(session) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SteadyPalette.mint)
            }

            if editing {
                TextField("Session name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SteadyPalette.ink)
                    .focused($nameFocused)
                    .onSubmit { commitName() }
                    .onExitCommand { editing = false }
            } else {
                Text(store.title(for: session))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SteadyPalette.ink)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { beginEditing() }
            }

            Spacer(minLength: 8)

            stateLabel

            Button { onOpen() } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? SteadyPalette.ink : SteadyPalette.muted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Open session")

            Menu { sessionMenu } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SteadyPalette.muted)
                    .frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                metadata("cpu", session.shortModel.isEmpty ? session.kind.displayName : session.shortModel)
                if session.contextTokens > 0 { metadata("circle.hexagongrid", "\(shortTokens(session.contextTokens)) ctx") }
                if session.worktree { metadata("arrow.triangle.branch", "worktree") }
                Spacer(minLength: 4)
                if let number = session.prNumber {
                    Button { store.openPR(session) } label: {
                        Label("#\(number)", systemImage: "arrow.triangle.pull")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "8b91ff"))
                    }
                    .buttonStyle(.plain)
                    .help(session.prRepo ?? "Open pull request")
                }
            }

            HStack(spacing: 7) {
                if session.profile.label != "Default" { metadata("person", session.profile.label) }
                if !session.visibleRepository.isEmpty { metadata("shippingbox", session.visibleRepository) }
                if !session.branch.isEmpty { metadata("arrow.triangle.branch", session.branch) }
                if session.state == .done { metadata("clock", relativeTime(session.modified)) }
            }
        }
    }

    @ViewBuilder private var stateLabel: some View {
        switch session.state {
        case .running:
            HStack(spacing: 5) {
                TypingDots()
                Text("Rodando")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.orange)
        case .done:
            Text("Concluída")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SteadyPalette.mint)
        }
    }

    @ViewBuilder private var sessionMenu: some View {
        Button(store.isPinned(session) ? "Unpin" : "Pin") { store.togglePin(session) }
        Button("Rename") { beginEditing() }
        Divider()
        Button("Open in Steady") { onOpen() }
        Button("Resume in Terminal") { store.openInTerminal(session) }
        if session.pid != nil {
            Divider()
            Button("End session", role: .destructive) { store.terminate(session) }
        }
    }

    private func metadata(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(Color(hex: "92959b"))
            .lineLimit(1)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hex: "16191d").opacity(hovering ? 0.90 : 0.72))
    }

    private var borderColor: Color { SteadyPalette.line }

    private var stateColor: Color {
        switch session.state {
        case .running: return .orange
        case .done: return SteadyPalette.mint
        }
    }
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
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SteadyPalette.ink)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)

                BrandIcon(context: context, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SteadyStores.shared.sessions.title(for: session))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SteadyPalette.ink)
                        .lineLimit(1)
                    Text("\(session.project)  ·  \(session.profile.label)\(session.branch.isEmpty ? "" : "  ·  " + session.branch)")
                        .font(.system(size: 12))
                        .foregroundStyle(SteadyPalette.muted)
                        .lineLimit(1)
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
