import SwiftUI

enum PaneApp: String, CaseIterable, Identifiable {
    case claude, slack, codex, github, linear, notion, figma, gmail, calendar, links
    var id: String { rawValue }
    var context: SteadyContext { SteadyData.context(rawValue) ?? SteadyData.contexts[0] }
    var comingSoon: Bool { self == .slack || self == .figma }

    @MainActor @ViewBuilder func view(onSnooze: @escaping () -> Void, onResolve: @escaping () -> Void) -> some View {
        switch self {
        case .claude: ClaudeSessionsPanel(onSnooze: onSnooze, onResolve: onResolve)
        case .codex: CodexSessionsPanel(onSnooze: onSnooze, onResolve: onResolve)
        case .linear: LinearPanel(onSnooze: onSnooze, onResolve: onResolve)
        case .notion: NotionPanel(onSnooze: onSnooze, onResolve: onResolve)
        case .slack: ComingSoonPanel(id: "slack", onSnooze: onSnooze, onResolve: onResolve)
        case .figma: ComingSoonPanel(id: "figma", onSnooze: onSnooze, onResolve: onResolve)
        case .calendar: CalendarPanel(onSnooze: onSnooze, onResolve: onResolve)
        case .gmail: MailPanel(onSnooze: onSnooze, onResolve: onResolve)
        case .github: GitHubPanel(onSnooze: onSnooze, onResolve: onResolve)
        case .links: LinksPanel(onSnooze: onSnooze, onResolve: onResolve)
        }
    }
}

enum WorkLayout: String, CaseIterable, Identifiable {
    case single, split2, triple, quad
    var id: String { rawValue }
    var paneCount: Int { switch self { case .single: 1; case .split2: 2; case .triple: 3; case .quad: 4 } }
    var symbol: String {
        switch self {
        case .single: return "square"
        case .split2: return "rectangle.split.2x1"
        case .triple: return "rectangle.split.3x1"
        case .quad: return "rectangle.split.2x2"
        }
    }
}

struct WorkspaceView: View {
    @State private var layout: WorkLayout = .single
    @State private var panes: [PaneApp] = [.claude, .linear, .codex, .github]
    @State private var focused = 0
    @AppStorage("steady.onboardingDone") private var onboardingDone = false
    @State private var toast: String?
    @State private var toastToken = 0
    @State private var commandOpen = false
    @State private var settingsOpen = false
    @State private var lastAuto = Date()

    private let triage = SteadyStores.shared.triage
    private let settings = SteadyStores.shared.settings
    private let heartbeat = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var visibleTools: [PaneApp] { PaneApp.allCases.filter { !settings.isHidden($0.id) } }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(SteadyPalette.line).frame(height: 1)
                body(for: layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(calmBackground)
            if let toast { ToastView(text: toast) }
            if commandOpen {
                CommandPalette(tools: visibleTools, onClose: { commandOpen = false }) { app in
                    commandOpen = false
                    withAnimation(.easeInOut(duration: 0.22)) { panes[focused] = app }
                }
            }
            if !onboardingDone {
                OnboardingView { withAnimation(.easeInOut(duration: 0.3)) { onboardingDone = true } }
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .sheet(isPresented: $settingsOpen) { SettingsView { settingsOpen = false } }
        .background {
            Button("") { commandOpen = true }.keyboardShortcut("k", modifiers: .command).opacity(0)
            Button("") { commandOpen = false }.keyboardShortcut(.escape, modifiers: []).opacity(0)
        }
        .onReceive(heartbeat) { _ in autoRefresh() }
    }

    private var calmBackground: some View {
        ZStack {
            Color.black.opacity(0.22)
            RadialGradient(colors: [Color.white.opacity(0.06), .clear], center: UnitPoint(x: 0.5, y: -0.04), startRadius: 0, endRadius: 700)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Text("Steady").font(.system(size: 18, weight: .bold)).tracking(-0.6).foregroundStyle(SteadyPalette.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visibleTools) { app in
                        TopBarIcon(context: app.context, selected: panes[focused] == app, activity: activity(for: app), comingSoon: app.comingSoon, snoozed: triage.isSnoozed(app.id)) {
                            withAnimation(.easeInOut(duration: 0.22)) { panes[focused] = app }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            Spacer(minLength: 8)

            Button { commandOpen = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "command").font(.system(size: 12))
                    Text("K").font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(SteadyPalette.muted)
                .frame(width: 52, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(SteadyPalette.line))
            }
            .buttonStyle(.plain).help("Jump to a tool (⌘K)")

            Button { settingsOpen = true } label: {
                Image(systemName: "gearshape").font(.system(size: 15)).foregroundStyle(SteadyPalette.muted)
                    .frame(width: 38, height: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain).help("Settings")

            HStack(spacing: 4) {
                ForEach(WorkLayout.allCases) { option in
                    Button { withAnimation(.easeInOut(duration: 0.16)) { layout = option } } label: {
                        Image(systemName: option.symbol)
                            .font(.system(size: 15))
                            .foregroundStyle(layout == option ? Color.white : SteadyPalette.muted)
                            .frame(width: 40, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9).fill(layout == option ? Color.white.opacity(0.07) : .clear))
                            .contentShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .help("\(option.paneCount) pane\(option.paneCount == 1 ? "" : "s")")
                }
            }

        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffectCompat(in: Rectangle(), tint: .black.opacity(0.18))
    }

    @ViewBuilder private func body(for layout: WorkLayout) -> some View {
        switch layout {
        case .single:
            pane(0)
        case .split2:
            HSplitView { pane(0); pane(1) }
        case .triple:
            HSplitView {
                pane(0)
                VSplitView { pane(1); pane(2) }
            }
        case .quad:
            VSplitView {
                HSplitView { pane(0); pane(1) }
                HSplitView { pane(2); pane(3) }
            }
        }
    }

    private func pane(_ index: Int) -> some View {
        Pane(app: panes[index], isFocused: focused == index,
             onFocus: { focused = index },
             onChange: { panes[index] = $0 },
             onSnooze: { snooze(panes[index]) },
             onResolve: { resolve(panes[index]) })
            .frame(minWidth: 280, minHeight: 220, maxHeight: .infinity)
    }

    private func activity(for app: PaneApp) -> ToolActivity {
        if triage.isSnoozed(app.id) { return .none }
        let sessions = SteadyStores.shared.sessions
        switch app {
        case .claude: return ToolActivity(badge: sessions.claude.filter { $0.state == .running }.count)
        case .codex: return ToolActivity(badge: sessions.codex.filter { $0.state == .running }.count)
        case .gmail: return ToolActivity(badge: SteadyStores.shared.mail.unreadCount)
        case .github: return ToolActivity(badge: SteadyStores.shared.github.unreadCount)
        case .links: return ToolActivity(badge: SteadyStores.shared.links.dueCount)
        default: return .none
        }
    }

    private func snooze(_ app: PaneApp) {
        triage.snooze(app.id)
        flash("Snoozed \(app.context.name) · 1h")
    }

    private func resolve(_ app: PaneApp) {
        triage.clear(app.id)
        if let next = visibleTools.first(where: { $0 != app && !$0.comingSoon && activity(for: $0).active }) {
            withAnimation(.easeInOut(duration: 0.22)) { panes[focused] = next }
            flash("Resolved · next: \(next.context.name)")
        } else {
            flash("Resolved · all clear")
        }
    }

    private func flash(_ message: String) {
        toast = message
        toastToken += 1
        let token = toastToken
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toastToken == token { withAnimation { toast = nil } }
        }
    }

    private func autoRefresh() {
        let minutes = settings.autoRefreshMinutes
        guard minutes > 0, Date().timeIntervalSince(lastAuto) >= Double(minutes) * 60 else { return }
        lastAuto = Date()
        SteadyStores.shared.github.refresh()
        SteadyStores.shared.mail.refresh()
        SteadyStores.shared.calendar.refresh()
        SteadyStores.shared.linear.load()
        SteadyStores.shared.notion.load()
    }
}

struct ToolActivity {
    let badge: Int
    var active: Bool { badge > 0 }
    static let none = ToolActivity(badge: 0)
}

private struct TopBarIcon: View {
    let context: SteadyContext
    let selected: Bool
    let activity: ToolActivity
    let comingSoon: Bool
    let snoozed: Bool
    let action: () -> Void

    @State private var pulse = false

    private var lit: Bool { selected || activity.active }

    var body: some View {
        Button(action: action) {
            BrandIcon(context: context, size: 42)
                .saturation(snoozed ? 0 : (lit ? 1 : 0.25))
                .opacity(snoozed ? 0.3 : (lit ? 1 : 0.42))
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 15).fill(selected ? Color.white.opacity(0.09) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? Color.white.opacity(0.28) : .clear, lineWidth: 1.5))
                .overlay(alignment: .topTrailing) { badge }
                .overlay(alignment: .bottomTrailing) { cornerTag }
                .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var helpText: String {
        if comingSoon { return "\(context.name), coming soon" }
        if snoozed { return "\(context.name), snoozed" }
        return context.name
    }

    @ViewBuilder private var cornerTag: some View {
        if comingSoon {
            Text("soon").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: "0b0d0f"))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Capsule().fill(Color(hex: "cfd2d6")))
                .overlay(Capsule().stroke(SteadyPalette.canvas, lineWidth: 1.5))
                .offset(x: 3, y: 2)
        } else if snoozed {
            Image(systemName: "moon.zzz.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: "0b0d0f"))
                .frame(width: 15, height: 15)
                .background(Circle().fill(Color(hex: "cfd2d6")))
                .overlay(Circle().stroke(SteadyPalette.canvas, lineWidth: 1.5))
                .offset(x: 3, y: 2)
        }
    }

    private var badgeText: String { activity.badge > 99 ? "99+" : "\(activity.badge)" }

    @ViewBuilder private var badge: some View {
        if activity.badge > 0 {
            Text(badgeText)
                .font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: "102019"))
                .padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16)
                .background(Capsule().fill(SteadyPalette.mint))
                .overlay(Capsule().stroke(SteadyPalette.canvas, lineWidth: 1.5))
                .scaleEffect(pulse ? 1.0 : 0.9)
                .offset(x: 4, y: -2)
                .onAppear { withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) { pulse = true } }
        }
    }
}

private struct Pane: View {
    let app: PaneApp
    let isFocused: Bool
    let onFocus: () -> Void
    let onChange: (PaneApp) -> Void
    let onSnooze: () -> Void
    let onResolve: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(PaneApp.allCases) { option in
                        Button(option.context.name) { onChange(option) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        BrandIcon(context: app.context, size: 20)
                        Text(app.context.name).font(.system(size: 12, weight: .medium)).foregroundStyle(SteadyPalette.ink)
                        Image(systemName: "chevron.down").font(.system(size: 8)).foregroundStyle(SteadyPalette.muted)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 38)
            .background(Color.white.opacity(0.03))
            .contentShape(Rectangle())
            .onTapGesture { onFocus() }
            Rectangle().fill(SteadyPalette.line).frame(height: 1)

            app.view(onSnooze: onSnooze, onResolve: onResolve)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.28))
        .overlay(Rectangle().stroke(isFocused ? Color.white.opacity(0.3) : SteadyPalette.line, lineWidth: isFocused ? 1.5 : 1))
    }
}
