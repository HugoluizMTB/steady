import SwiftUI

struct OnboardingView: View {
    let onDone: () -> Void

    private let calendar = SteadyStores.shared.calendar
    private let mail = SteadyStores.shared.mail
    private let github = SteadyStores.shared.github
    private let notion = SteadyStores.shared.notion
    private let linear = SteadyStores.shared.linear

    var body: some View {
        ZStack {
            SteadyPalette.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    header
                    transparency
                    connections
                    footer
                }
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .padding(.horizontal, 28)
            }
        }
        .onAppear { github.loadIfNeeded() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Welcome to Steady").font(.system(size: 26, weight: .bold)).tracking(-0.6).foregroundStyle(SteadyPalette.ink)
            Text("Your work in one calm place — the sessions, calendar, mail and code you already have on this Mac.")
                .font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420)
        }
    }

    private var transparency: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill").font(.system(size: 18)).foregroundStyle(SteadyPalette.mint)
            VStack(alignment: .leading, spacing: 5) {
                Text("Everything stays on this Mac").font(.system(size: 13, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
                Text("Steady has no server and no account. It reads live from the apps already on your Mac, and keeps tokens in the macOS Keychain. Nothing is uploaded or sent to the cloud.")
                    .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(SteadyPalette.mint.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SteadyPalette.mint.opacity(0.18)))
    }

    private var connections: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connect once").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "b6b9be"))
                .padding(.leading, 2)
            ConnectionRow(contextID: "calendar", title: "Calendar", detail: "Your Mac's calendar accounts", state: calendarState) { calendar.connect() }
            ConnectionRow(contextID: "gmail", title: "Mail", detail: "Your Mac's mailbox", state: mailState) { mail.connect() }
            ConnectionRow(contextID: "github", title: "GitHub", detail: githubDetail, state: githubState) { github.refresh() }
            ConnectionRow(contextID: "notion", title: "Notion", detail: "Search your workspace", state: notionState) { notion.signIn() }
            ConnectionRow(contextID: "linear", title: "Linear", detail: "Your assigned issues", state: linearState) { linear.signIn() }
            ConnectionRow(contextID: "claude", title: "Claude & Codex", detail: "Local CLI sessions — nothing to connect", state: .local, action: nil)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: onDone) {
                Text("Enter Steady").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "102019")).frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
            Text("You can skip any and connect later from each tool.")
                .font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
        }
        .padding(.top, 4)
    }

    private var calendarState: ConnectionState { calendar.access == .granted ? .connected : .idle }
    private var mailState: ConnectionState { mail.access == .granted ? .connected : .idle }
    private var githubState: ConnectionState {
        switch github.access {
        case .ready: return .connected
        case .unknown: return github.loading ? .busy : .idle
        default: return .idle
        }
    }
    private var githubDetail: String { github.login.map { "Signed in as @\($0)" } ?? "Your gh CLI login" }
    private var notionState: ConnectionState {
        if notion.isConnected || notion.status == .ready { return .connected }
        return notion.status == .authorizing ? .busy : .idle
    }
    private var linearState: ConnectionState {
        if linear.isConnected || linear.status == .ready { return .connected }
        return linear.status == .authorizing ? .busy : .idle
    }
}

enum ConnectionState { case idle, busy, connected, local }

private struct ConnectionRow: View {
    let contextID: String
    let title: String
    let detail: String
    let state: ConnectionState
    let action: (() -> Void)?

    private var context: SteadyContext { SteadyData.context(contextID) ?? SteadyData.contexts[0] }

    var body: some View {
        HStack(spacing: 12) {
            BrandIcon(context: context, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(SteadyPalette.ink)
                Text(detail).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "16191d").opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(SteadyPalette.line))
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(SteadyPalette.mint).labelStyle(.titleAndIcon)
        case .busy:
            ProgressView().controlSize(.small)
        case .local:
            Text("On this Mac").font(.system(size: 11, weight: .medium)).foregroundStyle(SteadyPalette.muted)
                .padding(.horizontal, 10).frame(height: 28).overlay(Capsule().stroke(SteadyPalette.line))
        case .idle:
            Button { action?() } label: {
                Text("Connect").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "102019"))
                    .padding(.horizontal, 14).frame(height: 30).background(Capsule().fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
        }
    }
}
