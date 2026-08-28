import SwiftUI
import AppKit

struct GitHubPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void

    private let store = SteadyStores.shared.github
    @State private var section: Section = .notifications

    enum Section: String, CaseIterable { case notifications = "Inbox", prs = "PRs", repos = "Repos" }

    private var context: SteadyContext { SteadyData.context("github") ?? SteadyData.contexts[0] }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: context, title: "GitHub", subtitle: subtitle, onSnooze: onSnooze, onResolve: onResolve)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            content
        }
        .onAppear { store.loadIfNeeded() }
    }

    private var subtitle: String {
        switch store.access {
        case .unknown: return "GitHub"
        case .missing: return "gh CLI not found"
        case .unauth: return "Not signed in to gh"
        case .ready:
            let account = store.login.map { "@\($0)" } ?? ""
            return "\(store.unreadCount) unread  ·  \(account)"
        }
    }

    @ViewBuilder private var content: some View {
        switch store.access {
        case .missing: GitHubNoticeView(icon: "terminal", title: "gh CLI not found", message: "Install GitHub CLI (brew install gh) and sign in with gh auth login, then reopen this pane.")
        case .unauth: GitHubNoticeView(icon: "person.crop.circle.badge.xmark", title: "Sign in to gh", message: "Run gh auth login in a terminal, then hit refresh.")
        case .unknown, .ready: ready
        }
    }

    private var ready: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            Group {
                switch section {
                case .notifications: notificationsView
                case .prs: prsView
                case .repos: reposView
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(Section.allCases, id: \.self) { item in
                    segment(item)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
            Spacer()
            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SteadyPalette.muted).frame(width: 30, height: 30)
                    .overlay(Circle().stroke(SteadyPalette.line))
            }
            .buttonStyle(.plain)
            .disabled(store.loading)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func segment(_ item: Section) -> some View {
        Button { section = item } label: {
            Text(item.rawValue).font(.system(size: 12, weight: .medium))
                .foregroundStyle(section == item ? SteadyPalette.ink : SteadyPalette.muted)
                .padding(.horizontal, 12).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(section == item ? Color.white.opacity(0.08) : .clear))
        }
        .buttonStyle(.plain)
    }

    private var notificationsView: some View {
        listOrEmpty(store.notifications.isEmpty, empty: "Inbox zero.") {
            ForEach(store.notifications) { item in
                GHNotificationRow(item: item) { store.open(item.url) }
            }
        }
    }

    private var prsView: some View {
        listOrEmpty(store.reviewPRs.isEmpty && store.myPRs.isEmpty, empty: "No open pull requests.") {
            if !store.reviewPRs.isEmpty {
                GHSectionLabel(text: "Awaiting your review")
                ForEach(store.reviewPRs) { pr in GHPullRequestRow(pr: pr) { store.open(pr.url) } }
            }
            if !store.myPRs.isEmpty {
                GHSectionLabel(text: "Your open PRs")
                ForEach(store.myPRs) { pr in GHPullRequestRow(pr: pr) { store.open(pr.url) } }
            }
        }
    }

    private var reposView: some View {
        listOrEmpty(store.repos.isEmpty, empty: "No repositories.") {
            ForEach(store.repos) { repo in GHRepoRow(repo: repo) { store.open(repo.url) } }
        }
    }

    @ViewBuilder private func listOrEmpty<Content: View>(_ isEmpty: Bool, empty: String, @ViewBuilder content: () -> Content) -> some View {
        if isEmpty {
            VStack(spacing: 8) {
                if store.loading { ProgressView().controlSize(.small) }
                else { Text(empty).font(.system(size: 12)).foregroundStyle(SteadyPalette.muted) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) { content() }
                    .padding(16)
            }
        }
    }
}

private struct GHSectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(hex: "b6b9be"))
            .padding(.top, 6).padding(.leading, 2)
    }
}

private struct GHNotificationRow: View {
    let item: GHNotification
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Circle().fill(item.unread ? SteadyPalette.mint : Color.clear)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(item.unread ? Color.clear : SteadyPalette.lineStrong))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.system(size: 13, weight: item.unread ? .semibold : .medium))
                        .foregroundStyle(SteadyPalette.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.repo).font(.system(size: 11)).foregroundStyle(Color(hex: "a9acb1")).lineLimit(1)
                        ReasonTag(reason: item.reason)
                    }
                }
                Spacer(minLength: 8)
                Text(relativeTime(item.updated)).font(.system(size: 10)).foregroundStyle(SteadyPalette.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: "16191d").opacity(item.unread ? 0.85 : 0.5)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(SteadyPalette.line))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

private struct ReasonTag: View {
    let reason: String
    var body: some View {
        Text(reason.replacingOccurrences(of: "_", with: " "))
            .font(.system(size: 9, weight: .semibold)).foregroundStyle(SteadyPalette.muted)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.06)))
    }
}

private struct GHPullRequestRow: View {
    let pr: GHPullRequest
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Image(systemName: "arrow.triangle.pull").font(.system(size: 12)).foregroundStyle(SteadyPalette.positive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title).font(.system(size: 13, weight: .medium)).foregroundStyle(SteadyPalette.ink).lineLimit(1)
                    Text("\(pr.repo)  ·  #\(pr.number)").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(relativeTime(pr.updated)).font(.system(size: 10)).foregroundStyle(SteadyPalette.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: "16191d").opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(SteadyPalette.line))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

private struct GHRepoRow: View {
    let repo: GHRepo
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed.fill")
                    .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name).font(.system(size: 13, weight: .medium)).foregroundStyle(SteadyPalette.ink).lineLimit(1)
                    if !repo.detail.isEmpty {
                        Text(repo.detail).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if repo.stars > 0 {
                    Label("\(repo.stars)", systemImage: "star.fill").font(.system(size: 10)).foregroundStyle(SteadyPalette.muted)
                }
                Text(relativeTime(repo.pushed)).font(.system(size: 10)).foregroundStyle(SteadyPalette.muted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: "16191d").opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(SteadyPalette.line))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
}

private struct GitHubNoticeView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(SteadyPalette.muted)
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(SteadyPalette.ink)
            Text(message).font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func relativeTime(_ date: Date?) -> String {
    guard let date else { return "" }
    let seconds = Date().timeIntervalSince(date)
    if seconds < 60 { return "now" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    if seconds < 86400 { return "\(Int(seconds / 3600))h" }
    if seconds < 604800 { return "\(Int(seconds / 86400))d" }
    return "\(Int(seconds / 604800))w"
}
