import AppKit
import Darwin
import Foundation

struct AgentSession: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case claude
        case codex

        var displayName: String {
            switch self {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            }
        }

        var profilePrefix: String {
            switch self {
            case .claude: return ".claude"
            case .codex: return ".codex"
            }
        }
    }

    enum State: Sendable { case waiting, working, idle }

    let id: String
    let kind: Kind
    let pid: Int32?
    let profile: AgentProfile
    let cwd: String
    let repository: String
    let branch: String
    let title: String
    let filePath: String
    let modified: Date
    let state: State
    let activity: String
    let model: String
    let contextTokens: Int
    let prNumber: Int?
    let prRepo: String?
    let prURL: String?
    let worktree: Bool

    var project: String { cwd.isEmpty ? "—" : URL(fileURLWithPath: cwd).lastPathComponent }
    var persistentKey: String { "\(kind.rawValue)|\(profile.root)|\(id)" }
    var visibleRepository: String { prRepo ?? repository }

    var shortModel: String {
        model.isEmpty ? "" : model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}

struct AgentProfile: Identifiable, Hashable, Sendable {
    let kind: AgentSession.Kind
    let root: String

    var id: String { "\(kind.rawValue)|\(root)" }

    var label: String {
        let name = URL(fileURLWithPath: root).lastPathComponent
        guard name != kind.profilePrefix else { return "Default" }
        return String(name.dropFirst(kind.profilePrefix.count + 1))
    }
}

@MainActor
@Observable
final class SessionStore {
    private(set) var claude: [AgentSession] = []
    private(set) var codex: [AgentSession] = []
    private(set) var loading = false
    private(set) var profiles: [AgentProfile] = []

    private let metadata = SessionMetadataStore()
    private var revision = 0
    private var timer: Timer?

    init() {
        refreshProfiles()
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    func profiles(for kind: AgentSession.Kind) -> [AgentProfile] {
        profiles.filter { $0.kind == kind }
    }

    func load() {
        refreshProfiles()
        let claudeProfiles = profiles(for: .claude)
        let codexProfiles = profiles(for: .codex)
        loading = claude.isEmpty && codex.isEmpty

        Task {
            let result = await Task.detached(priority: .utility) {
                SessionScanner.openSessions(claudeProfiles: claudeProfiles, codexProfiles: codexProfiles)
            }.value
            claude = result.0
            codex = result.1
            loading = false
        }
    }

    func title(for session: AgentSession) -> String {
        _ = revision
        return metadata.metadata(for: session.persistentKey).customName ?? session.title
    }

    func isPinned(_ session: AgentSession) -> Bool {
        _ = revision
        return metadata.metadata(for: session.persistentKey).isPinned
    }

    func rename(_ session: AgentSession) {
        let alert = NSAlert()
        alert.messageText = "Name this session"
        alert.informativeText = session.project
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = title(for: session)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        metadata.setName(value.isEmpty || value == session.title ? nil : value, for: session.persistentKey)
        revision += 1
    }

    func togglePin(_ session: AgentSession) {
        metadata.setPinned(!isPinned(session), for: session.persistentKey)
        revision += 1
    }

    func openInTerminal(_ session: AgentSession) {
        launch(command: resumeCommand(for: session), in: session.cwd)
    }

    func openPR(_ session: AgentSession) {
        if let url = session.prURL.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
    }

    func startNewSession(kind: AgentSession.Kind, profile: AgentProfile) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Start \(kind.displayName)"
        panel.message = "Choose the folder for the new \(kind.displayName) session."

        guard panel.runModal() == .OK, let folder = panel.url?.path else { return }
        launch(command: newSessionCommand(kind: kind, profile: profile), in: folder)
        Task {
            try? await Task.sleep(for: .seconds(1))
            load()
        }
    }

    func terminate(_ session: AgentSession) {
        guard let pid = session.pid else { return }
        let alert = NSAlert()
        alert.messageText = "End \(session.kind.displayName) session?"
        alert.informativeText = "\(title(for: session)) will stop. You can resume it later if the agent supports resuming this session."
        alert.addButton(withTitle: "End session")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        _ = kill(pid, SIGTERM)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            load()
        }
    }

    private func refreshProfiles() {
        let discovered = SessionScanner.discoverProfiles(home: NSHomeDirectory())
        profiles = discovered.claude + discovered.codex
    }

    private func resumeCommand(for session: AgentSession) -> String {
        switch session.kind {
        case .claude:
            return "CLAUDE_CONFIG_DIR=\(shellQuote(session.profile.root)) claude --resume \(shellQuote(session.id))"
        case .codex:
            return "CODEX_HOME=\(shellQuote(session.profile.root)) codex resume \(shellQuote(session.id))"
        }
    }

    private func newSessionCommand(kind: AgentSession.Kind, profile: AgentProfile) -> String {
        switch kind {
        case .claude:
            return "CLAUDE_CONFIG_DIR=\(shellQuote(profile.root)) claude"
        case .codex:
            return "CODEX_HOME=\(shellQuote(profile.root)) codex"
        }
    }

    private func launch(command: String, in directory: String) {
        let cwd = directory.isEmpty ? NSHomeDirectory() : directory
        let command = "cd \(shellQuote(cwd)); \(command)"
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        NSAppleScript(source: "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell")?.executeAndReturnError(nil)
    }

    private func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum SessionScanner {
    struct RunningAgent: Sendable {
        let kind: AgentSession.Kind
        let pid: Int32
        let ppid: Int32
        let uuid: String?
        let cwd: String
        let command: String
    }

    struct RepositoryContext: Sendable {
        let repository: String
        let branch: String
        let worktree: Bool

        static let empty = RepositoryContext(repository: "", branch: "", worktree: false)
    }

    static func discoverProfiles(home: String) -> (claude: [AgentProfile], codex: [AgentProfile]) {
        (profiles(home: home, kind: .claude), profiles(home: home, kind: .codex))
    }

    static func run(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    static func runningAgents() -> [RunningAgent] {
        guard let out = run("/bin/ps", ["-axo", "pid=,ppid=,command="]) else { return [] }
        var agents: [RunningAgent] = []

        for raw in out.split(separator: "\n") {
            let fields = raw.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]), let ppid = Int32(fields[1]) else { continue }
            let command = String(fields[2])
            let lower = command.lowercased()
            if lower.contains("tmux ") || lower.contains("grep ") || lower.contains("claude-usage") || lower.contains(" mcp") || lower.contains("firebase") { continue }

            let words = command.split(whereSeparator: \.isWhitespace).map(String.init)
            let hasClaude = words.contains { $0 == "claude" || $0.hasSuffix("/claude") }
            let hasCodex = words.contains { $0 == "codex" || $0.hasSuffix("/codex") }
            let headless = lower.contains(" -p") || lower.contains("--print") || lower.contains("stream-json")

            if hasClaude && !headless {
                agents.append(RunningAgent(kind: .claude, pid: pid, ppid: ppid, uuid: extractUUID(command), cwd: "", command: command))
            } else if hasCodex && !headless {
                agents.append(RunningAgent(kind: .codex, pid: pid, ppid: ppid, uuid: extractUUID(command), cwd: "", command: command))
            }
        }

        let agentPids = Set(agents.map(\.pid))
        let topLevel = agents.filter { !agentPids.contains($0.ppid) }
        let cwdMap = cwds(pids: topLevel.map(\.pid))
        return topLevel.map { agent in
            RunningAgent(kind: agent.kind, pid: agent.pid, ppid: agent.ppid, uuid: agent.uuid, cwd: cwdMap[agent.pid] ?? "", command: agent.command)
        }
    }

    static func openSessions(claudeProfiles: [AgentProfile], codexProfiles: [AgentProfile]) -> ([AgentSession], [AgentSession]) {
        let agents = runningAgents().filter { !$0.cwd.isEmpty && $0.cwd != "/" }
        var repositories: [String: RepositoryContext] = [:]
        var claude: [String: AgentSession] = [:]
        var codex: [String: AgentSession] = [:]

        for agent in agents {
            let context: RepositoryContext
            if let cached = repositories[agent.cwd] {
                context = cached
            } else {
                let loaded = repositoryContext(at: agent.cwd)
                repositories[agent.cwd] = loaded
                context = loaded
            }

            switch agent.kind {
            case .claude:
                if let session = claudeSession(for: agent, profiles: claudeProfiles, repository: context) {
                    claude[session.persistentKey] = session
                }
            case .codex:
                let session = codexSession(for: agent, profiles: codexProfiles, repository: context)
                codex[session.persistentKey] = session
            }
        }

        return (Array(claude.values), Array(codex.values))
    }

    private static func profiles(home: String, kind: AgentSession.Kind) -> [AgentProfile] {
        let manager = FileManager.default
        let homeURL = URL(fileURLWithPath: home)
        let names = (try? manager.contentsOfDirectory(atPath: home)) ?? []
        let prefix = kind.profilePrefix
        let discovered = names.filter { $0 == prefix || $0.hasPrefix(prefix + "-") }
            .map { homeURL.appendingPathComponent($0).path }
            .filter { path in
                var isDirectory: ObjCBool = false
                return manager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            }

        let roots = discovered.isEmpty ? [homeURL.appendingPathComponent(prefix).path] : discovered
        return roots.sorted { lhs, rhs in
            let leftDefault = URL(fileURLWithPath: lhs).lastPathComponent == prefix
            let rightDefault = URL(fileURLWithPath: rhs).lastPathComponent == prefix
            if leftDefault != rightDefault { return leftDefault }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        .map { AgentProfile(kind: kind, root: $0) }
    }

    private static func cwds(pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty,
              let out = run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fpn", "-p", pids.map(String.init).joined(separator: ",")])
        else { return [:] }
        var map: [Int32: String] = [:]
        var current: Int32 = 0
        for line in out.split(separator: "\n") {
            if line.hasPrefix("p") { current = Int32(line.dropFirst()) ?? 0 }
            else if line.hasPrefix("n") { map[current] = String(line.dropFirst()) }
        }
        return map
    }

    private static func extractUUID(_ text: String) -> String? {
        let pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    private static func claudeSession(for agent: RunningAgent, profiles: [AgentProfile], repository: RepositoryContext) -> AgentSession? {
        let profile = profile(for: agent.command, profiles: profiles, kind: .claude)
        let encoded = encode(agent.cwd)
        let orderedProfiles = [profile] + profiles.filter { $0 != profile }

        for candidate in orderedProfiles {
            let directory = URL(fileURLWithPath: candidate.root).appendingPathComponent("projects").appendingPathComponent(encoded)
            if let uuid = agent.uuid {
                let file = directory.appendingPathComponent(uuid + ".jsonl")
                if FileManager.default.fileExists(atPath: file.path) {
                    let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                    return parseClaude(file, date: date, cwd: agent.cwd, pid: agent.pid, profile: candidate, repository: repository)
                }
            } else if let file = newestJSONL(directory) {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
                return parseClaude(file, date: date, cwd: agent.cwd, pid: agent.pid, profile: candidate, repository: repository)
            }
        }

        return nil
    }

    private static func codexSession(for agent: RunningAgent, profiles: [AgentProfile], repository: RepositoryContext) -> AgentSession {
        let profile = profile(for: agent.command, profiles: profiles, kind: .codex)
        return AgentSession(
            id: agent.uuid ?? "pid-\(agent.pid)", kind: .codex, pid: agent.pid, profile: profile,
            cwd: agent.cwd, repository: repository.repository, branch: repository.branch,
            title: URL(fileURLWithPath: agent.cwd).lastPathComponent, filePath: "", modified: Date(),
            state: .working, activity: "Codex is working", model: "codex", contextTokens: 0,
            prNumber: nil, prRepo: nil, prURL: nil, worktree: repository.worktree
        )
    }

    private static func profile(for command: String, profiles: [AgentProfile], kind: AgentSession.Kind) -> AgentProfile {
        if let matching = profiles.first(where: { command.contains($0.root) }) { return matching }
        if let defaultProfile = profiles.first(where: { URL(fileURLWithPath: $0.root).lastPathComponent == kind.profilePrefix }) {
            return defaultProfile
        }
        return profiles.first ?? AgentProfile(kind: kind, root: NSHomeDirectory() + "/\(kind.profilePrefix)")
    }

    private static func repositoryContext(at cwd: String) -> RepositoryContext {
        let branch = run("/usr/bin/git", ["-C", cwd, "branch", "--show-current"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let remote = run("/usr/bin/git", ["-C", cwd, "remote", "get-url", "origin"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let repository = repositoryName(remote) ?? URL(fileURLWithPath: cwd).lastPathComponent
        return RepositoryContext(repository: repository, branch: branch, worktree: isWorktree(cwd))
    }

    private static func repositoryName(_ remote: String) -> String? {
        guard !remote.isEmpty else { return nil }
        let normalized = remote.replacingOccurrences(of: ".git", with: "")
            .replacingOccurrences(of: ":", with: "/")
        let parts = normalized.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return parts.suffix(2).joined(separator: "/")
    }

    private static func encode(_ path: String) -> String {
        String(path.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    private static func newestJSONL(_ directory: URL) -> URL? {
        let manager = FileManager.default
        guard let items = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return items.filter { $0.pathExtension == "jsonl" }
            .max { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left < right
            }
    }

    private static func isWorktree(_ cwd: String) -> Bool {
        guard !cwd.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd + "/.git", isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue
    }

    private static func head(_ url: URL, bytes: Int = 16_384) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: bytes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func tail(_ url: URL, bytes: UInt64 = 131_072) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > bytes ? size - bytes : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func object(_ line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func text(from content: Any?) -> String {
        if let string = content as? String { return string }
        if let blocks = content as? [[String: Any]] {
            for block in blocks where block["type"] as? String == "text" {
                if let value = block["text"] as? String { return value }
            }
        }
        return ""
    }

    private static func toolName(from content: Any?) -> String? {
        guard let blocks = content as? [[String: Any]] else { return nil }
        return blocks.first(where: { $0["type"] as? String == "tool_use" })?["name"] as? String
    }

    private static func parseClaude(_ url: URL, date: Date, cwd: String, pid: Int32, profile: AgentProfile, repository: RepositoryContext) -> AgentSession {
        var branch = ""
        var title = ""
        for line in head(url).split(separator: "\n").prefix(150) {
            guard let object = object(line) else { continue }
            if branch.isEmpty, let value = object["gitBranch"] as? String, !value.isEmpty { branch = value }
            if title.isEmpty, object["type"] as? String == "user", let message = object["message"] as? [String: Any] {
                title = text(from: message["content"])
            }
            if !branch.isEmpty && !title.isEmpty { break }
        }

        var model = ""
        var stop = ""
        var lastAssistant = ""
        var lastTool = ""
        var lastConversation = ""
        var contextTokens = 0
        var prNumber: Int?
        var prRepository: String?
        var prURL: String?

        for line in tail(url).split(separator: "\n") {
            guard let object = object(line) else { continue }
            switch object["type"] as? String {
            case "pr-link":
                prNumber = object["prNumber"] as? Int
                prRepository = object["prRepository"] as? String
                prURL = object["prUrl"] as? String
            case "assistant":
                lastConversation = "assistant"
                guard let message = object["message"] as? [String: Any] else { continue }
                if let value = message["model"] as? String { model = value }
                stop = message["stop_reason"] as? String ?? ""
                if let usage = message["usage"] as? [String: Any] {
                    contextTokens = (usage["input_tokens"] as? Int ?? 0)
                        + (usage["cache_read_input_tokens"] as? Int ?? 0)
                        + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                }
                let value = text(from: message["content"])
                if !value.isEmpty { lastAssistant = value }
                if let tool = toolName(from: message["content"]) { lastTool = tool }
            case "user":
                lastConversation = "user"
            default:
                break
            }
        }

        let isRecent = Date().timeIntervalSince(date) < 25
        let state: AgentSession.State
        if isRecent && lastConversation != "assistant" { state = .working }
        else if lastConversation == "assistant" && stop == "end_turn" { state = .waiting }
        else if isRecent { state = .working }
        else { state = .idle }

        let activity: String
        switch state {
        case .waiting: activity = lastAssistant.isEmpty ? "Waiting for your reply" : lastAssistant
        case .working: activity = lastTool.isEmpty ? "Working…" : "Using \(lastTool)…"
        case .idle: activity = lastAssistant.isEmpty ? "Idle" : lastAssistant
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentSession(
            id: url.deletingPathExtension().lastPathComponent, kind: .claude, pid: pid, profile: profile,
            cwd: cwd, repository: repository.repository, branch: branch.isEmpty ? repository.branch : branch,
            title: cleanTitle.isEmpty ? "Untitled session" : String(cleanTitle.prefix(100)), filePath: url.path,
            modified: date, state: state, activity: String(activity.prefix(280)), model: model,
            contextTokens: contextTokens, prNumber: prNumber, prRepo: prRepository, prURL: prURL,
            worktree: repository.worktree
        )
    }
}
