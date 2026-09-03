import SwiftUI
import AppKit

struct NotionPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void

    private let provider = SteadyStores.shared.notion
    @State private var draft = ""

    private var context: SteadyContext { SteadyData.context("notion")! }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: context, title: "Notion", subtitle: subtitle, onSnooze: onSnooze, onResolve: onResolve)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            content
        }
        .onAppear { if provider.isConnected, provider.status == .disconnected { provider.load() } }
    }

    private var subtitle: String {
        switch provider.status {
        case .disconnected: return "Sign in with Notion"
        case .authorizing: return "Waiting for authorization…"
        case .loading: return "Searching…"
        case .ready: return "\(provider.results.count) result\(provider.results.count == 1 ? "" : "s")"
        case .failed: return "Connection error"
        }
    }

    @ViewBuilder private var content: some View {
        switch provider.status {
        case .disconnected: signIn
        case .authorizing: authorizing
        case .failed(let message): failure(message)
        case .loading, .ready: connected
        }
    }

    private var connected: some View {
        VStack(spacing: 0) {
            searchBar
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            if provider.status == .loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !provider.results.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(provider.results) { result in
                            NotionResultRow(result: result) { open(result.url) }
                        }
                    }
                    .padding(16)
                }
            } else if !provider.rawText.isEmpty {
                ScrollView {
                    Text(provider.rawText).font(.system(size: 12)).foregroundStyle(Color(hex: "c8cbd0"))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            } else {
                Text(provider.query.isEmpty ? "Search your workspace." : "Nothing found.")
                    .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
                TextField("Search Notion", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(SteadyPalette.ink)
                    .onSubmit { provider.search(draft) }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(SteadyPalette.line))

            Button { provider.disconnect() } label: {
                Text("Disconnect").font(.system(size: 11, weight: .medium)).foregroundStyle(SteadyPalette.muted)
                    .padding(.horizontal, 10).frame(height: 32).overlay(Capsule().stroke(SteadyPalette.line))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var signIn: some View {
        VStack(spacing: 16) {
            BrandIcon(context: context, size: 60)
            Text("Sign in with Notion").font(.system(size: 21, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
            Text("One click. Steady registers itself with Notion's MCP and authorizes with PKCE. No app to create, no keys.")
                .font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 360)
            Button { provider.signIn() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.forward.app")
                    Text("Sign in with Notion").fontWeight(.semibold)
                }
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
            Button("Cancel") { provider.disconnect() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failure(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
            Text(message).font(.system(size: 13)).foregroundStyle(SteadyPalette.muted).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Try again") { provider.signIn() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.mint)
                Button("Reset") { provider.disconnect() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.muted)
            }
        }
        .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(_ url: String) {
        guard let target = URL(string: url) else { return }
        NSWorkspace.shared.open(target)
    }
}

private struct NotionResultRow: View {
    let result: NotionResult
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title).font(.system(size: 13, weight: .medium)).foregroundStyle(SteadyPalette.ink).lineLimit(1)
                    if !result.snippet.isEmpty {
                        Text(result.snippet).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                    } else if !result.url.isEmpty {
                        Text(result.url).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(Color(hex: "45484d"))
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: "16191d").opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(SteadyPalette.line))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}
