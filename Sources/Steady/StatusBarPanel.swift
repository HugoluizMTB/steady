import SwiftUI
import AppKit
import PRMenubar
import ClaudeUsage
import ColorPickerKit
import ClipboardKit

struct TransparentWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(nsView.window) }
    }
    private static func apply(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        (window as? NSPanel)?.hidesOnDeactivate = false
    }
}

struct IslandContent: View {
    @ObservedObject var prStore: PRStore
    @Environment(\.openWindow) private var openWindow
    @State private var selected: IslandTool?

    private let compactWidth: CGFloat = 360
    private let overviewHeight: CGFloat = 295
    private let detailHeight: CGFloat = 295

    var body: some View {
        VStack(spacing: 8) {
            header
            GlassEffectContainer(spacing: 10) {
                stage
            }
        }
        .padding(10)
        .frame(width: compactWidth)
        .animation(.snappy(duration: 0.24), value: selected)
    }

    private var header: some View {
        HStack(spacing: 9) {
            if selected == nil {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selected = nil }
                } label: {
                    Image(systemName: "chevron.backward")
                }
                .buttonStyle(.glass)
            }

            Text(selected?.title ?? "Steady")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.3)

            Spacer()

            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "macwindow")
            }
            .buttonStyle(.glass)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    @ViewBuilder private var stage: some View {
        if selected == nil {
            overview
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(height: overviewHeight, alignment: .top)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                stageContent
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.bottom, 6)
            }
            .frame(height: detailHeight, alignment: .top)
        }
    }

    @ViewBuilder private var stageContent: some View {
        switch selected {
        case .pr:
            PullRequestsPanel(store: prStore)
        case .usage:
            ClaudeUsagePanel()
        case .ports:
            PortsPanel()
        case .colors:
            ColorPickerPanel()
        case .clipboard:
            ClipboardPanel(manager: SteadyStores.shared.clipboard)
        case .snap:
            CodeSnapLauncher().frame(height: 240)
        case nil:
            overview
        }
    }

    private var overview: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible())
            ],
            spacing: 5
        ) {
            ForEach(IslandTool.allCases) { item in
                ToolCard(item: item) {
                    withAnimation(.snappy(duration: 0.22)) { selected = item }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct ToolCard: View {
    let item: IslandTool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 27, height: 27)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(hovering ? 0.16 : 0.08))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 0.6)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .tracking(-0.2)

                    Text(item.subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(hovering ? 0.72 : 0.30))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 45)
            .padding(.horizontal, 10)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(hovering ? 0.15 : 0.075),
                            .white.opacity(hovering ? 0.07 : 0.025),
                            .white.opacity(0.015)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.24), .white.opacity(0.06)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.7
                )
        }
        .scaleEffect(hovering ? 1.012 : 1)
        .animation(.snappy(duration: 0.16), value: hovering)
        .onHover { hovering = $0 }
    }
}

enum IslandTool: String, CaseIterable, Identifiable {
    case pr, usage, ports, colors, clipboard, snap
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pr: return "arrow.triangle.pull"
        case .usage: return "chart.bar.xaxis"
        case .ports: return "network"
        case .colors: return "eyedropper"
        case .clipboard: return "doc.on.clipboard"
        case .snap: return "curlybraces"
        }
    }

    var title: String {
        switch self {
        case .pr: return "Pull Requests"
        case .usage: return "Claude Usage"
        case .ports: return "Ports"
        case .colors: return "Colors"
        case .clipboard: return "Clipboard"
        case .snap: return "Code Snap"
        }
    }

    var subtitle: String {
        switch self {
        case .pr: return "Open PRs & CI"
        case .usage: return "Token usage"
        case .ports: return "Listening ports"
        case .colors: return "Pick screen colors"
        case .clipboard: return "Clipboard history"
        case .snap: return "Code screenshots"
        }
    }
}
