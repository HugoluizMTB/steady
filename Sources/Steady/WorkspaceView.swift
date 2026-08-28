import SwiftUI

enum PaneApp: String, CaseIterable, Identifiable {
    case claude, slack, codex, github, linear, notion, figma, gmail, calendar
    var id: String { rawValue }
    var context: SteadyContext { SteadyData.context(rawValue) ?? SteadyData.contexts[0] }
    var comingSoon: Bool { self == .slack || self == .figma }

    @MainActor @ViewBuilder func view() -> some View {
        switch self {
        case .claude: ClaudeSessionsPanel(onSnooze: {}, onResolve: {})
        case .codex: CodexSessionsPanel(onSnooze: {}, onResolve: {})
        case .linear: LinearPanel(onSnooze: {}, onResolve: {})
        case .notion: NotionPanel(onSnooze: {}, onResolve: {})
        case .slack: ComingSoonPanel(id: "slack", onSnooze: {}, onResolve: {})
        case .figma: ComingSoonPanel(id: "figma", onSnooze: {}, onResolve: {})
        case .calendar: CalendarPanel(onSnooze: {}, onResolve: {})
        case .gmail: MailPanel(onSnooze: {}, onResolve: {})
        case .github: GitHubPanel(onSnooze: {}, onResolve: {})
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

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(SteadyPalette.line).frame(height: 1)
                body(for: layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(calmBackground)
            if !onboardingDone {
                OnboardingView { withAnimation(.easeInOut(duration: 0.3)) { onboardingDone = true } }
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
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
                    ForEach(PaneApp.allCases) { app in
                        TopBarIcon(context: app.context, selected: panes[focused] == app, activity: activity(for: app), comingSoon: app.comingSoon) {
                            withAnimation(.easeInOut(duration: 0.22)) { panes[focused] = app }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            Spacer(minLength: 8)

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
        .glassEffect(.regular.tint(.black.opacity(0.18)), in: Rectangle())
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
             onChange: { panes[index] = $0 })
            .frame(minWidth: 280, minHeight: 220, maxHeight: .infinity)
    }

    private func activity(for app: PaneApp) -> ToolActivity {
        let sessions = SteadyStores.shared.sessions
        switch app {
        case .claude: return ToolActivity(badge: sessions.claude.filter { $0.state == .running }.count)
        case .codex: return ToolActivity(badge: sessions.codex.filter { $0.state == .running }.count)
        case .gmail: return ToolActivity(badge: SteadyStores.shared.mail.unreadCount)
        case .github: return ToolActivity(badge: SteadyStores.shared.github.unreadCount)
        default: return .none
        }
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
    let action: () -> Void

    @State private var pulse = false

    private var lit: Bool { selected || activity.active }

    var body: some View {
        Button(action: action) {
            BrandIcon(context: context, size: 42)
                .saturation(lit ? 1 : 0.25)
                .opacity(lit ? 1 : 0.42)
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 15).fill(selected ? Color.white.opacity(0.09) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected ? Color.white.opacity(0.28) : .clear, lineWidth: 1.5))
                .overlay(alignment: .topTrailing) { badge }
                .overlay(alignment: .bottomTrailing) { soonTag }
                .contentShape(RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
        .help(comingSoon ? "\(context.name) — coming soon" : context.name)
    }

    @ViewBuilder private var soonTag: some View {
        if comingSoon {
            Text("soon").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: "0b0d0f"))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Capsule().fill(Color(hex: "cfd2d6")))
                .overlay(Capsule().stroke(SteadyPalette.canvas, lineWidth: 1.5))
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

            app.view()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black.opacity(0.28))
        .overlay(Rectangle().stroke(isFocused ? Color.white.opacity(0.3) : SteadyPalette.line, lineWidth: isFocused ? 1.5 : 1))
    }
}
