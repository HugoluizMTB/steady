import SwiftUI

enum PaneApp: String, CaseIterable, Identifiable {
    case claude, slack, codex, linear, notion, figma, gmail, calendar
    var id: String { rawValue }
    var context: SteadyContext { SteadyData.context(rawValue) ?? SteadyData.contexts[0] }

    @MainActor @ViewBuilder func view() -> some View {
        switch self {
        case .claude: ClaudeSessionsPanel(onSnooze: {}, onResolve: {})
        case .codex: CodexSessionsPanel(onSnooze: {}, onResolve: {})
        case .linear: LinearPanel(onSnooze: {}, onResolve: {})
        case .slack: SlackPanel(onSnooze: {}, onResolve: {})
        default: GenericPanel(id: rawValue, onSnooze: {}, onResolve: {})
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
    @State private var panes: [PaneApp] = [.claude, .linear, .codex, .slack]
    @State private var focused = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            body(for: layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(calmBackground)
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
                        Button { withAnimation(.easeInOut(duration: 0.22)) { panes[focused] = app } } label: {
                            BrandIcon(context: app.context, size: 42)
                                .saturation(panes[focused] == app ? 1 : 0.25)
                                .opacity(panes[focused] == app ? 1 : 0.42)
                                .padding(9)
                                .background(RoundedRectangle(cornerRadius: 15).fill(panes[focused] == app ? Color.white.opacity(0.09) : .clear))
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(panes[focused] == app ? Color.white.opacity(0.28) : .clear, lineWidth: 1.5))
                                .contentShape(RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                        .help(app.context.name)
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
