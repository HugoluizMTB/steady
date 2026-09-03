import SwiftUI
import AppKit

struct LinearPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void
    private let provider = SteadyStores.shared.linear
    @State private var workspaceFilter: String?
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
        case .ready:
            let accounts = provider.connections.count
            let base = "\(provider.issues.count) active  ·  \(accounts) account\(accounts == 1 ? "" : "s")"
            return provider.newIDs.isEmpty ? base : "\(provider.newIDs.count) new  ·  " + base
        case .failed: return "Connection error"
        }
    }

    @ViewBuilder private var content: some View {
        switch provider.status {
        case .disconnected: signIn
        case .authorizing: authorizing
        case .loading: ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message): failure(message)
        case .ready: ready
        }
    }

    private var ready: some View {
        VStack(spacing: 0) {
            accountsBar
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            if provider.issues.isEmpty {
                Text("Nothing assigned to you").font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
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

    private var accountsBar: some View {
        HStack(spacing: 6) {
            ForEach(provider.connections) { connection in
                let active = workspaceFilter == connection.label
                HStack(spacing: 5) {
                    Button {
                        if connection.needsReauth { provider.reconnect(connection.id) }
                        else { workspaceFilter = active ? nil : connection.label }
                    } label: {
                        HStack(spacing: 6) {
                            if connection.needsReauth {
                                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(Color(hex: "f2994a"))
                            } else {
                                Circle().fill(Color(hex: "7472ff")).frame(width: 6, height: 6)
                            }
                            Text(connection.label).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(active ? Color(hex: "102019") : Color(hex: "d4d6da")).lineLimit(1)
                            if connection.needsReauth {
                                Text("Reconnect").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: "f2994a"))
                            }
                        }
                        .padding(.leading, 10).frame(height: 28)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(connection.needsReauth ? "Session expired — click to reconnect" : connection.label)
                    Button { provider.disconnect(connection.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(active ? Color(hex: "102019").opacity(0.7) : SteadyPalette.muted)
                            .frame(width: 20, height: 28)
                    }
                    .buttonStyle(.plain)
                }
                .background(Capsule().fill(active ? SteadyPalette.mint : Color.clear))
                .overlay(Capsule().stroke(connection.needsReauth ? Color(hex: "f2994a").opacity(0.5) : (active ? Color.clear : SteadyPalette.line)))
            }
            Button { provider.signIn() } label: {
                HStack(spacing: 5) { Image(systemName: "plus"); Text("Add account") }
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(SteadyPalette.mint)
                    .padding(.horizontal, 10).frame(height: 28).overlay(Capsule().stroke(SteadyPalette.mint.opacity(0.35)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var signIn: some View {
        VStack(spacing: 16) {
            BrandIcon(context: context, size: 60)
            Text("Sign in with Linear").font(.system(size: 21, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
            Text("One click — Steady registers itself with Linear and authorizes with PKCE. Have two workspaces? Connect one, then hit “Add account” for the other.")
                .font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 360)
            Button { provider.signIn() } label: {
                HStack(spacing: 8) { Image(systemName: "arrow.up.forward.app"); Text("Sign in with Linear").fontWeight(.semibold) }
                    .font(.system(size: 14)).foregroundStyle(Color(hex: "102019"))
                    .padding(.horizontal, 22).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 11).fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }

    private var authorizing: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Approve Steady in your browser…").font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
            Text("For a second account, sign in to that workspace in the browser first.").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).multilineTextAlignment(.center)
            Button("Cancel") { provider.load() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
            Text(message).font(.system(size: 13)).foregroundStyle(SteadyPalette.muted).multilineTextAlignment(.center)
            Button("Try again") { provider.signIn() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.mint)
        }
        .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension LinearPanel {
    func group(_ types: [String]) -> [LinearIssue] {
        provider.issues
            .filter { types.contains($0.statusType) && (workspaceFilter == nil || $0.workspace == workspaceFilter) }
            .sorted { ($0.priority == 0 ? 5 : $0.priority) < ($1.priority == 0 ? 5 : $1.priority) }
    }

    @ViewBuilder func section(_ title: String, _ items: [LinearIssue]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(SteadyPalette.muted)
                ForEach(items) { issue in
                    IssueRow(issue: issue,
                             isNew: provider.newIDs.contains(issue.id),
                             showWorkspace: provider.connections.count > 1)
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
    var showWorkspace: Bool = false
    @State private var hovering = false

    var body: some View {
        Button {
            if let url = URL(string: issue.url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 12) {
                Circle().fill(priorityColor).frame(width: 8, height: 8)
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
                        if showWorkspace, !issue.workspace.isEmpty {
                            Text(issue.workspace).font(.system(size: 9, weight: .semibold)).foregroundStyle(Color(hex: "9a99e0"))
                                .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color(hex: "7472ff").opacity(0.16)))
                        }
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

    private var priorityColor: Color {
        switch issue.priority {
        case 1: return Color(hex: "eb5757")
        case 2: return Color(hex: "f2994a")
        case 3: return Color(hex: "f2c94c")
        case 4: return Color(hex: "8f9299")
        default: return SteadyPalette.muted.opacity(0.4)
        }
    }
}
