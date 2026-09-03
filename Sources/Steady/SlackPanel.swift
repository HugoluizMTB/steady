import SwiftUI
import AppKit

struct SlackPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void
    private let provider = SteadyStores.shared.slack
    private var context: SteadyContext { SteadyData.context("slack")! }
    @State private var clientId = ""
    @State private var clientSecret = ""

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: context, title: "Slack", subtitle: subtitle,
                        onSnooze: onSnooze, onResolve: onResolve)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            content
        }
        .onAppear {
            clientId = provider.savedClientId
            clientSecret = provider.savedClientSecret
            if provider.isConnected { provider.load() }
        }
    }

    private var subtitle: String {
        switch provider.status {
        case .disconnected: return "Connect the official Slack MCP"
        case .authorizing: return "Waiting for authorization…"
        case .loading: return "Connecting…"
        case .ready: return "Connected"
        case .failed: return "Connection error"
        }
    }

    @ViewBuilder private var content: some View {
        switch provider.status {
        case .disconnected:
            connect
        case .authorizing:
            centered { ProgressView().controlSize(.small); Text("Approve Steady in your browser…").font(.system(size: 13)).foregroundStyle(SteadyPalette.muted); Button("Cancel") { provider.disconnect() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.muted) }
        case .loading:
            centered { ProgressView().controlSize(.small) }
        case .failed(let message):
            centered {
                Image(systemName: "exclamationmark.triangle").font(.title).foregroundStyle(.orange)
                Text(message).font(.system(size: 13)).foregroundStyle(SteadyPalette.muted).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Try again") { provider.authorize(clientId: clientId, clientSecret: clientSecret) }.buttonStyle(.plain).foregroundStyle(SteadyPalette.mint)
                    Button("Reset") { provider.disconnect() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.muted)
                }
            }
        case .ready:
            centered {
                BrandIcon(context: context, size: 52)
                Text("Slack connected").font(.system(size: 18, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
                Text("\(provider.toolCount) Slack tools available via the official MCP.")
                    .font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
                Button("Disconnect") { provider.disconnect() }.buttonStyle(.plain).foregroundStyle(SteadyPalette.muted).font(.system(size: 12))
            }
        }
    }

    private func centered<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 12) { content() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
    }

    private var connect: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Connect Slack").font(.system(size: 20, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
                Text("Slack’s MCP needs a registered app (no zero-setup: Slack requires a client secret). One-time: create a Slack app, add the redirect URI, add User Token Scopes, and paste its Client ID + Secret.")
                    .font(.system(size: 13)).foregroundStyle(SteadyPalette.muted).fixedSize(horizontal: false, vertical: true)

                redirectRow
                field("Client ID", text: $clientId, secure: false)
                field("Client secret", text: $clientSecret, secure: true)

                HStack(spacing: 12) {
                    Button { provider.authorize(clientId: clientId, clientSecret: clientSecret) } label: {
                        Text("Authorize with Slack").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: "102019"))
                            .padding(.horizontal, 18).frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 10).fill(SteadyPalette.mint))
                    }
                    .buttonStyle(.plain)
                    .disabled(clientId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://api.slack.com/apps")!)
                    } label: {
                        Text("Create Slack app ↗").font(.system(size: 13)).foregroundStyle(SteadyPalette.mint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(30)
        }
    }

    private var redirectRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Redirect URL (add under OAuth & Permissions)").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
            HStack {
                Text(OAuthLoopback.redirectURI).font(.system(size: 12).monospaced()).foregroundStyle(SteadyPalette.mint)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(OAuthLoopback.redirectURI, forType: .string)
                } label: { Image(systemName: "doc.on.doc").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted) }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "0f1215")))
        }
    }

    private func field(_ label: String, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
            Group {
                if secure { SecureField("", text: text) } else { TextField("", text: text) }
            }
            .textFieldStyle(.plain).foregroundStyle(.white).font(.system(size: 13).monospaced())
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: "0f1215")))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(SteadyPalette.lineStrong))
        }
    }
}
