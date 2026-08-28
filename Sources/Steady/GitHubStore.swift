import Foundation
import AppKit

@MainActor
@Observable
final class GitHubStore {
    enum Access { case unknown, ready, unauth, missing }

    private(set) var access: Access = .unknown
    private(set) var login: String?
    private(set) var notifications: [GHNotification] = []
    private(set) var myPRs: [GHPullRequest] = []
    private(set) var reviewPRs: [GHPullRequest] = []
    private(set) var repos: [GHRepo] = []
    private(set) var loading = false

    var unreadCount: Int { notifications.filter { $0.unread }.count }

    func loadIfNeeded() {
        if access == .unknown { load() }
    }

    func refresh() { load() }

    func load() {
        loading = true
        Task {
            let auth = await Task.detached { GitHubBridge.login() }.value
            if auth.ghMissing { access = .missing; loading = false; return }
            if !auth.ok || auth.unauth { access = .unauth; loading = false; return }

            access = .ready
            login = GitHubBridge.parseLogin(auth)

            async let notificationsResult = Task.detached { GitHubBridge.notifications() }.value
            async let myResult = Task.detached { GitHubBridge.myPRs() }.value
            async let reviewResult = Task.detached { GitHubBridge.reviewPRs() }.value
            async let reposResult = Task.detached { GitHubBridge.repos() }.value
            let (notificationsData, myData, reviewData, reposData) = await (notificationsResult, myResult, reviewResult, reposResult)

            notifications = GitHubBridge.parseNotifications(notificationsData.output)
            myPRs = GitHubBridge.parsePRs(myData.output)
            reviewPRs = GitHubBridge.parsePRs(reviewData.output)
            repos = GitHubBridge.parseRepos(reposData.output)
            loading = false
        }
    }

    func open(_ url: String) {
        guard let target = URL(string: url) else { return }
        NSWorkspace.shared.open(target)
    }
}
