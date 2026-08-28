import Foundation

struct GHNotification: Identifiable, Sendable {
    let id: String
    let repo: String
    let title: String
    let type: String
    let reason: String
    let unread: Bool
    let url: String
    let updated: Date?
}

struct GHPullRequest: Identifiable, Sendable {
    let id: String
    let title: String
    let repo: String
    let number: Int
    let url: String
    let updated: Date?
}

struct GHRepo: Identifiable, Sendable {
    let id: String
    let name: String
    let fullName: String
    let detail: String
    let url: String
    let pushed: Date?
    let isPrivate: Bool
    let stars: Int
}

enum GitHubBridge {
    struct RunResult: Sendable {
        let output: Data
        let stderr: String
        let ok: Bool
        let ghMissing: Bool

        var unauth: Bool {
            stderr.localizedCaseInsensitiveContains("gh auth login")
                || stderr.localizedCaseInsensitiveContains("not logged in")
                || stderr.localizedCaseInsensitiveContains("authentication")
        }
    }

    static func login() -> RunResult { run(["api", "user", "--jq", ".login"]) }
    static func notifications() -> RunResult { run(["api", "notifications"]) }
    static func myPRs() -> RunResult { run(["search", "prs", "--author=@me", "--state=open", "--limit", "30", "--json", "title,url,number,updatedAt"]) }
    static func reviewPRs() -> RunResult { run(["search", "prs", "--review-requested=@me", "--state=open", "--limit", "30", "--json", "title,url,number,updatedAt"]) }
    static func repos() -> RunResult { run(["repo", "list", "--limit", "20", "--json", "name,nameWithOwner,description,url,pushedAt,isPrivate,stargazerCount"]) }

    static func parseLogin(_ result: RunResult) -> String? {
        let value = String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func parseNotifications(_ data: Data) -> [GHNotification] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let repository = item["repository"] as? [String: Any]
            let subject = item["subject"] as? [String: Any]
            let html = htmlURL(from: subject?["url"] as? String) ?? (repository?["html_url"] as? String ?? "")
            return GHNotification(
                id: id,
                repo: repository?["full_name"] as? String ?? "",
                title: subject?["title"] as? String ?? "",
                type: subject?["type"] as? String ?? "",
                reason: item["reason"] as? String ?? "",
                unread: item["unread"] as? Bool ?? true,
                url: html,
                updated: iso(item["updated_at"] as? String)
            )
        }
    }

    static func parsePRs(_ data: Data) -> [GHPullRequest] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            guard let url = item["url"] as? String else { return nil }
            return GHPullRequest(
                id: url,
                title: item["title"] as? String ?? "",
                repo: repo(fromURL: url),
                number: item["number"] as? Int ?? 0,
                url: url,
                updated: iso(item["updatedAt"] as? String)
            )
        }
    }

    static func parseRepos(_ data: Data) -> [GHRepo] {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { item in
            let fullName = item["nameWithOwner"] as? String ?? item["name"] as? String ?? ""
            guard !fullName.isEmpty else { return nil }
            return GHRepo(
                id: fullName,
                name: item["name"] as? String ?? fullName,
                fullName: fullName,
                detail: item["description"] as? String ?? "",
                url: item["url"] as? String ?? "",
                pushed: iso(item["pushedAt"] as? String),
                isPrivate: item["isPrivate"] as? Bool ?? false,
                stars: item["stargazerCount"] as? Int ?? 0
            )
        }
    }

    private static func run(_ args: [String]) -> RunResult {
        guard let gh = resolvedPath else {
            return RunResult(output: Data(), stderr: "gh not found", ok: false, ghMissing: true)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = args
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            let outData = output.fileHandleForReading.readDataToEndOfFile()
            let errData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return RunResult(output: outData, stderr: String(decoding: errData, as: UTF8.self), ok: process.terminationStatus == 0, ghMissing: false)
        } catch {
            return RunResult(output: Data(), stderr: error.localizedDescription, ok: false, ghMissing: false)
        }
    }

    private static let resolvedPath: String? = {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) { return path }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: shell)
        probe.arguments = ["-lc", "command -v gh"]
        let pipe = Pipe()
        probe.standardOutput = pipe
        probe.standardError = Pipe()
        do {
            try probe.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            probe.waitUntilExit()
            let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) { return path }
        } catch {}
        return nil
    }()

    private static func iso(_ text: String?) -> Date? {
        guard let text else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func repo(fromURL url: String) -> String {
        let parts = (URLComponents(string: url)?.path ?? "").split(separator: "/")
        guard parts.count >= 2 else { return "" }
        return "\(parts[0])/\(parts[1])"
    }

    private static func htmlURL(from api: String?) -> String? {
        guard let api, api.contains("api.github.com") else { return api }
        return api
            .replacingOccurrences(of: "api.github.com/repos", with: "github.com")
            .replacingOccurrences(of: "/pulls/", with: "/pull/")
    }
}
