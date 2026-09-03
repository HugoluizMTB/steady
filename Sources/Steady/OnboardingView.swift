import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome, calendarPermission, mailPermission, connections
}

struct OnboardingView: View {
    let onDone: () -> Void

    @State private var step: OnboardingStep = .welcome

    private let calendar = SteadyStores.shared.calendar
    private let mail = SteadyStores.shared.mail
    private let github = SteadyStores.shared.github
    private let notion = SteadyStores.shared.notion
    private let linear = SteadyStores.shared.linear

    var body: some View {
        ZStack {
            SteadyPalette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                progressDots
                Group {
                    switch step {
                    case .welcome: WelcomeStep { advance() }
                    case .calendarPermission: CalendarPermissionStep(store: calendar, onNext: advance)
                    case .mailPermission: MailPermissionStep(store: mail, onNext: advance)
                    case .connections: ConnectionsStep(github: github, notion: notion, linear: linear, onDone: onDone)
                    }
                }
                .transition(.opacity)
            }
            .frame(maxWidth: 540)
            .padding(.vertical, 44)
            .padding(.horizontal, 28)
        }
        .onAppear { github.loadIfNeeded() }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? SteadyPalette.mint : Color.white.opacity(0.12))
                    .frame(width: item == step ? 22 : 14, height: 4)
            }
        }
        .padding(.bottom, 28)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.22)) {
            if let next = OnboardingStep(rawValue: step.rawValue + 1) { step = next } else { onDone() }
        }
    }
}

private struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Welcome to Steady").font(.system(size: 26, weight: .bold)).tracking(-0.6).foregroundStyle(SteadyPalette.ink)
                Text("Your work in one calm place: the sessions, calendar, mail and code you already have on this Mac.")
                    .font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420)
            }

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

            Text("Next, we'll ask for two permissions, Calendar and Mail, one at a time.")
                .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)

            Button(action: onNext) {
                Text("Get started").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "102019")).frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CalendarPermissionStep: View {
    let store: CalendarStore
    let onNext: () -> Void
    @State private var requested = false

    var body: some View {
        PermissionStep(
            contextID: "calendar",
            title: "Calendar access",
            detail: "Steady shows your upcoming events from every calendar account already on this Mac: iCloud, Google, Exchange.",
            granted: store.access == .granted,
            denied: store.access == .denied,
            onAllow: { requested = true; store.connect() },
            onNext: onNext
        )
        .onChange(of: store.access) { _, access in
            if requested, access != .unknown { onNext() }
        }
    }
}

private struct MailPermissionStep: View {
    let store: MailStore
    let onNext: () -> Void
    @State private var requested = false

    var body: some View {
        PermissionStep(
            contextID: "gmail",
            title: "Mail access",
            detail: "Steady reads and sends through the Mail app already set up on this Mac. No new login, just a one-time Automation permission.",
            granted: store.access == .granted,
            denied: store.access == .denied,
            onAllow: { requested = true; store.connect() },
            onNext: onNext
        )
        .onChange(of: store.access) { _, access in
            if requested, access != .unknown { onNext() }
        }
    }
}

private struct PermissionStep: View {
    let contextID: String
    let title: String
    let detail: String
    let granted: Bool
    let denied: Bool
    let onAllow: () -> Void
    let onNext: () -> Void

    private var context: SteadyContext { SteadyData.context(contextID) ?? SteadyData.contexts[0] }

    var body: some View {
        VStack(spacing: 20) {
            BrandIcon(context: context, size: 56)
            VStack(spacing: 8) {
                Text(title).font(.system(size: 20, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
                Text(detail).font(.system(size: 13)).foregroundStyle(SteadyPalette.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 400)
            }

            if granted {
                Label("Access granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(SteadyPalette.mint)
            } else if denied {
                Label("Access denied. You can enable it later in System Settings", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(hex: "f2994a"))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button(action: onAllow) {
                    Text("Allow \(title)").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: "102019")).frame(maxWidth: .infinity).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 12).fill(SteadyPalette.mint))
                }
                .buttonStyle(.plain)
                .disabled(granted)
                .opacity(granted ? 0.5 : 1)

                Button("Not now", action: onNext)
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
            }
        }
    }
}

private struct ConnectionsStep: View {
    let github: GitHubStore
    let notion: NotionProvider
    let linear: LinearProvider
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text("Connect your tools").font(.system(size: 20, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
                Text("Optional, and one click each. Skip any of these. You can connect from the tool itself later.")
                    .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 400)
            }

            VStack(spacing: 8) {
                ConnectionRow(contextID: "github", title: "GitHub", detail: githubDetail, state: githubState) { github.refresh() }
                ConnectionRow(contextID: "notion", title: "Notion", detail: "Search your workspace", state: notionState) { notion.signIn() }
                ConnectionRow(contextID: "linear", title: "Linear", detail: "Your assigned issues", state: linearState) { linear.signIn() }
                ConnectionRow(contextID: "claude", title: "Claude & Codex", detail: "Local CLI sessions, nothing to connect", state: .local, action: nil)
            }

            Button(action: onDone) {
                Text("Enter Steady").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "102019")).frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
        }
    }

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
