import SwiftUI
import AppKit

struct LinearPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void
    private let provider = SteadyStores.shared.linear
    private var context: SteadyContext { SteadyData.context("linear")! }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: context, title: "Linear", subtitle: subtitle,
                        onSnooze: onSnooze, onResolve: onResolve)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            content
        }
        .onAppear { if provider.isConnected { provider.load() } }
    }

    private var subtitle: String {
        switch provider.status {
        case .disconnected: return "Sign in with Linear"
        case .authorizing: return "Waiting for authorization…"
        case .loading: return "Loading issues…"
        case .ready: return provider.newIDs.isEmpty ? "\(provider.issues.count) active" : "\(provider.newIDs.count) new  ·  \(provider.issues.count) active"
        case .failed: return "Connection error"
        }
    }

    @ViewBuilder private var content: some View {
        switch provider.status {
        case .disconnected:
            signIn
        case .authorizing:
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Approve Steady in your browser…").font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
                Button("Cancel") { provider.disconnect() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
                Text(message).font(.system(size: 13)).foregroundStyle(SteadyPalette.muted).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Try again") { provider.signIn() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.mint)
                    Button("Reset") { provider.disconnect() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.muted)
                }
            }
            .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if provider.issues.isEmpty {
                VStack(spacing: 10) {
                    Text("Nothing assigned to you").font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
                    Button("Disconnect") { provider.disconnect() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.muted).font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        section("In Progress", group(["started"]))
                        section("Todo", group(["unstarted", "triage"]))
                        section("Backlog", group(["backlog"]))
                    }
                    .padding(20)
                }
            }
        }
    }

    private var signIn: some View {
        VStack(spacing: 16) {
            BrandIcon(context: context, size: 60)
            Text("Sign in with Linear").font(.system(size: 21, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
            Text("One click. Steady registers itself with Linear (like an MCP) and authorizes with PKCE — no app to create, no keys.")
                .font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
            Button {
                provider.signIn()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.app")
                    Text("Sign in with Linear").fontWeight(.semibold)
                }
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "102019"))
                .padding(.horizontal, 22).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 11).fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}

extension LinearPanel {
    func group(_ types: [String]) -> [LinearIssue] {
        SteadyStores.shared.linear.issues
            .filter { types.contains($0.statusType) }
            .sorted { ($0.priority == 0 ? 5 : $0.priority) < ($1.priority == 0 ? 5 : $1.priority) }
    }

    @ViewBuilder func section(_ title: String, _ items: [LinearIssue]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(SteadyPalette.muted)
                ForEach(items) { issue in
                    IssueRow(issue: issue, isNew: SteadyStores.shared.linear.newIDs.contains(issue.id))
                }
            }
        }
    }
}

func linearStatusColor(_ type: String) -> Color {
    switch type {
    case "started": return Color(hex: "f2c94c")
    case "unstarted": return Color(hex: "9aa0a6")
    case "backlog": return Color(hex: "6b6e74")
    case "triage": return Color(hex: "f2994a")
    default: return Color(hex: "8f9299")
    }
}

private struct IssueRow: View {
    let issue: LinearIssue
    var isNew: Bool = false
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: issue.url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 12) {
                if let bar = priorityColor {
                    RoundedRectangle(cornerRadius: 3).fill(bar).frame(width: 3, height: 32)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(issue.title).font(.system(size: 13, weight: .medium)).foregroundStyle(SteadyPalette.ink).lineLimit(1)
                        if isNew {
                            Text("NEW").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: "102019"))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(SteadyPalette.mint))
                        }
                    }
                    HStack(spacing: 8) {
                        Text(issue.identifier).font(.system(size: 11).monospaced()).foregroundStyle(SteadyPalette.muted)
                        HStack(spacing: 5) {
                            Circle().fill(linearStatusColor(issue.statusType)).frame(width: 7, height: 7)
                            Text(issue.statusName).foregroundStyle(Color(hex: "8b8e95"))
                        }
                        .font(.system(size: 11))
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(hovering ? SteadyPalette.ink : Color(hex: "45484d"))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "16191d").opacity(hovering ? 0.9 : 0.6)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isNew ? SteadyPalette.mint.opacity(0.25) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var priorityColor: Color? {
        switch issue.priority {
        case 1: return Color(hex: "eb5757")
        case 2: return Color(hex: "f2994a")
        case 3: return Color(hex: "f2c94c")
        case 4: return Color(hex: "8f9299")
        default: return nil
        }
    }
}
