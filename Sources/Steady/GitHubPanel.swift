import SwiftUI
import AppKit

struct GitHubPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void

    private let store = SteadyStores.shared.github

    private var context: SteadyContext { SteadyData.context("github") ?? SteadyData.contexts[0] }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: context, title: "GitHub", subtitle: subtitle, onSnooze: onSnooze, onResolve: onResolve)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            content
        }
        .onAppear { store.loadIfNeeded() }
        .sheet(item: Binding(get: { store.detailPR }, set: { if $0 == nil { store.closeDetail() } })) { pr in
            PRDetailView(store: store, pr: pr)
        }
    }

    private var subtitle: String {
        switch store.access {
        case .unknown: return "GitHub"
        case .missing: return "gh CLI not found"
        case .unauth: return "Not signed in to gh"
        case .ready:
            let account = store.login.map { "@\($0)" } ?? ""
            return "\(account)  ·  \(store.myPRs.count) open  ·  \(store.reviewPRs.count) to review"
        }
    }

    @ViewBuilder private var content: some View {
        switch store.access {
        case .missing: GitHubNoticeView(icon: "terminal", title: "gh CLI not found", message: "Install GitHub CLI (brew install gh) and sign in with gh auth login, then reopen this pane.")
        case .unauth: GitHubNoticeView(icon: "person.crop.circle.badge.xmark", title: "Sign in to gh", message: "Run gh auth login in a terminal, then hit refresh.")
        case .unknown, .ready: dashboard
        }
    }

    private var dashboard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                pullRequestTable
                bento
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            graphStrip
        }
        .padding(16)
    }

    // MARK: Pull request table

    private var taggedPRs: [TaggedPR] {
        store.reviewPRs.map { TaggedPR(pr: $0, tag: .review) } + store.myPRs.map { TaggedPR(pr: $0, tag: .mine) }
    }

    private var pullRequestTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pull requests").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "b6b9be"))
                Spacer()
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).foregroundStyle(SteadyPalette.muted)
                }
                .buttonStyle(.plain).disabled(store.loading)
            }
            if taggedPRs.isEmpty {
                Text(store.loading ? "Loading…" : "No open pull requests.")
                    .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(taggedPRs) { item in
                            PRRow(pr: item.pr, tag: item.tag) { store.openDetail(item.pr) }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "16191d").opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(SteadyPalette.line))
    }

    // MARK: Bento

    private var bento: some View {
        VStack(spacing: 10) {
            StreakCard(contributions: store.contributions)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(value: store.myPRs.count, label: "open PRs", icon: "arrow.triangle.pull", accent: false) { store.open("https://github.com/pulls") }
                StatTile(value: store.reviewPRs.count, label: "to review", icon: "eye.fill", accent: !store.reviewPRs.isEmpty) { store.open("https://github.com/pulls/review-requested") }
                StatTile(value: store.issuesCount, label: "issues", icon: "smallcircle.filled.circle", accent: false) { store.open("https://github.com/issues") }
                StatTile(value: store.dependabotCount, label: "dependabot", icon: "shippingbox.fill", accent: !(store.dependabotCount == 0)) { store.open("https://github.com/pulls?q=is%3Apr+is%3Aopen+author%3Aapp%2Fdependabot") }
                StatTile(value: store.unreadCount, label: "notifications", icon: "bell.fill", accent: store.unreadCount > 0) { store.open("https://github.com/notifications") }
                StatTile(value: store.repos.count, label: "repos", icon: "book.closed.fill", accent: false) { store.open("https://github.com/\(store.login ?? "")?tab=repositories") }
            }
        }
        .frame(width: 300)
    }

    // MARK: Contribution strip

    @ViewBuilder private var graphStrip: some View {
        if let contributions = store.contributions {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Contributions").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "b6b9be"))
                    Spacer()
                    Text("\(contributions.total) this year").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
                }
                ContributionGraph(weeks: contributions.weeks)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "16191d").opacity(0.4)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(SteadyPalette.line))
        }
    }
}

private enum PRTag { case review, mine }

private struct TaggedPR: Identifiable {
    let pr: GHPullRequest
    let tag: PRTag
    var id: String { (tag == .review ? "r:" : "m:") + pr.url }
}

private struct PRRow: View {
    let pr: GHPullRequest
    let tag: PRTag
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: tag == .review ? "eye.fill" : "arrow.triangle.pull")
                    .font(.system(size: 11)).foregroundStyle(tag == .review ? SteadyPalette.mint : SteadyPalette.positive)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title).font(.system(size: 13, weight: .medium)).foregroundStyle(SteadyPalette.ink).lineLimit(1)
                    Text("\(pr.repo)  ·  #\(pr.number)").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(tag == .review ? "review" : "yours")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(SteadyPalette.muted)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.white.opacity(0.06)))
                Text(relativeTime(pr.updated)).font(.system(size: 10)).foregroundStyle(SteadyPalette.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: "16191d").opacity(0.7)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(SteadyPalette.line))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    let icon: String
    let accent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(accent ? SteadyPalette.mint : SteadyPalette.muted)
                Text("\(value)").font(.system(size: 22, weight: .bold)).foregroundStyle(SteadyPalette.ink)
                Text(label).font(.system(size: 10)).foregroundStyle(SteadyPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "16191d").opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(accent ? SteadyPalette.mint.opacity(0.3) : SteadyPalette.line))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct StreakCard: View {
    let contributions: GHContributions?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill").font(.system(size: 20)).foregroundStyle(SteadyPalette.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(contributions?.currentStreak ?? 0) day streak").font(.system(size: 16, weight: .bold)).foregroundStyle(SteadyPalette.ink)
                Text("\(contributions?.longestStreak ?? 0) longest").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(SteadyPalette.mint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(SteadyPalette.mint.opacity(0.22)))
    }
}

private struct ContributionGraph: View {
    let weeks: [[GHDay]]

    private let levels = ["1b1f24", "0e4429", "006d32", "26a641", "39d353"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                            VStack(spacing: 3) {
                                ForEach(week) { day in
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(Color(hex: day.colorHex))
                                        .frame(width: 11, height: 11)
                                }
                            }
                            .id(index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onAppear { proxy.scrollTo(weeks.count - 1, anchor: .trailing) }
            }
            legend
        }
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(.system(size: 9)).foregroundStyle(SteadyPalette.muted)
            ForEach(levels, id: \.self) { hex in
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(hex: hex)).frame(width: 10, height: 10)
            }
            Text("More").font(.system(size: 9)).foregroundStyle(SteadyPalette.muted)
        }
    }
}

private struct PRDetailView: View {
    let store: GitHubStore
    let pr: GHPullRequest

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { store.closeDetail() } label: {
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(SteadyPalette.muted)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(SteadyPalette.ink).lineLimit(2)
                    Text("\(pr.repo)  ·  #\(pr.number)").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
                }
                Spacer(minLength: 8)
                Button { store.open(pr.url) } label: {
                    Label("Open", systemImage: "arrow.up.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: "102019")).padding(.horizontal, 12).frame(height: 28)
                        .background(Capsule().fill(SteadyPalette.mint))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            ScrollView {
                if store.loadingDetail {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 40)
                } else {
                    Text(rendered).font(.system(size: 13)).foregroundStyle(Color(hex: "d4d6da"))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
        }
        .frame(width: 600, height: 560)
        .background(SteadyPalette.canvas)
    }

    private var rendered: AttributedString {
        let body = store.detailBody.isEmpty ? "(No description)" : store.detailBody
        return (try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(body)
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
