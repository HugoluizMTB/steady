import Foundation
import AppKit

struct AgentSession: Identifiable, Sendable {
    enum Kind: Sendable { case claude, codex }
    enum State: Sendable { case waiting, working, idle }

    let id: String
    let kind: Kind
    let cwd: String
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

    var shortModel: String {
        model.isEmpty ? "" : model
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }
}

@MainActor
@Observable
final class SessionStore {
    private(set) var claude: [AgentSession] = []
    private(set) var codex: [AgentSession] = []
    private(set) var loading = false

    private(set) var pinned: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "sessions.pinned") ?? [])
    private var names: [String: String] = (UserDefaults.standard.dictionary(forKey: "sessions.names") as? [String: String]) ?? [:]

    private let claudeRoots = ["/.claude-pessoal/projects", "/.claude-empresa/projects", "/.claude/projects"]
    private let codexRoot = "/.codex/sessions"
    private var timer: Timer?

    init() {
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    func load() {
        let home = NSHomeDirectory()
        let cRoots = claudeRoots.map { home + $0 }
        let xRoot = home + codexRoot
        loading = claude.isEmpty && codex.isEmpty
        Task {
            let result = await Task.detached(priority: .utility) {
                SessionScanner.openSessions(claudeRoots: cRoots, codexRoot: xRoot)
            }.value
            self.claude = result.0
            self.codex = result.1
            self.loading = false
        }
    }

    func title(for session: AgentSession) -> String {
        names[session.id] ?? session.title
    }

    func rename(_ session: AgentSession) {
        let alert = NSAlert()
        alert.messageText = "Rename session"
        alert.informativeText = session.project
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = title(for: session)
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { names[session.id] = nil } else { names[session.id] = value }
            UserDefaults.standard.set(names, forKey: "sessions.names")
        }
    }

    func isPinned(_ session: AgentSession) -> Bool { pinned.contains(session.id) }

    func togglePin(_ session: AgentSession) {
        if pinned.contains(session.id) { pinned.remove(session.id) } else { pinned.insert(session.id) }
        UserDefaults.standard.set(Array(pinned), forKey: "sessions.pinned")
    }

    func openInTerminal(_ session: AgentSession) {
        let cwd = session.cwd.isEmpty ? NSHomeDirectory() : session.cwd
        let command = session.kind == .claude
            ? "cd \(shellQuote(cwd)); claude --resume \(session.id)"
            : "cd \(shellQuote(cwd)); codex resume \(session.id)"
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        NSAppleScript(source: "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell")?.executeAndReturnError(nil)
    }

    func openPR(_ session: AgentSession) {
        if let url = session.prURL.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
    }

    private func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum SessionScanner {
    struct RunningAgent { let kind: AgentSession.Kind; let pid: Int32; let uuid: String?; let cwd: String }

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
        guard let out = run("/bin/ps", ["-axo", "pid=,command="]) else { return [] }
        var claude: [(Int32, String?)] = []
        var codex: [(Int32, String?)] = []
        for raw in out.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " "), let pid = Int32(line[..<space]) else { continue }
            let command = String(line[line.index(after: space)...])
            let lower = command.lowercased()
            if lower.contains("tmux ") || lower.contains("grep ") || lower.contains("claude-usage") || lower.contains(" mcp") || lower.contains("firebase") { continue }
            let program = command.split(separator: " ").first.map(String.init) ?? ""
            let isClaude = program == "claude" || program.hasSuffix("/claude")
            let isCodex = program == "codex" || program.hasSuffix("/codex")
            let headless = lower.contains(" -p") || lower.contains("--print") || lower.contains("stream-json")
            if isClaude && !headless {
                claude.append((pid, extractUUID(command)))
            } else if isCodex && !headless {
                codex.append((pid, extractUUID(command)))
            }
        }
        let cwdMap = cwds(pids: claude.map(\.0) + codex.map(\.0))
        return claude.map { RunningAgent(kind: .claude, pid: $0.0, uuid: $0.1, cwd: cwdMap[$0.0] ?? "") }
            + codex.map { RunningAgent(kind: .codex, pid: $0.0, uuid: $0.1, cwd: cwdMap[$0.0] ?? "") }
    }

    static func cwds(pids: [Int32]) -> [Int32: String] {
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

    static func extractUUID(_ text: String) -> String? {
        let pattern = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    static func encode(_ path: String) -> String {
        String(path.map { $0.isLetter || $0.isNumber ? $0 : "-" })
    }

    static func openSessions(claudeRoots: [String], codexRoot: String) -> ([AgentSession], [AgentSession]) {
        let agents = runningAgents()
        var claude: [String: AgentSession] = [:]
        var codex: [String: AgentSession] = [:]
        for agent in agents where !agent.cwd.isEmpty && agent.cwd != "/" {
            if agent.kind == .claude {
                let session = claudeSession(for: agent, roots: claudeRoots)
                claude[session.id] = session
            } else {
                let session = codexSession(for: agent, root: codexRoot)
                codex[session.id] = session
            }
        }
        return (Array(claude.values), Array(codex.values))
    }

    static func claudeSession(for agent: RunningAgent, roots: [String]) -> AgentSession {
        let encoded = encode(agent.cwd)
        var fileURL: URL?
        for root in roots {
            let dir = URL(fileURLWithPath: root).appendingPathComponent(encoded)
            if let uuid = agent.uuid {
                let candidate = dir.appendingPathComponent(uuid + ".jsonl")
                if FileManager.default.fileExists(atPath: candidate.path) { fileURL = candidate; break }
            } else if let newest = newestJSONL(dir) {
                fileURL = newest; break
            }
        }
        if let url = fileURL {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
            return parseClaude(url, date, cwd: agent.cwd)
        }
        return AgentSession(id: agent.uuid ?? "pid-\(agent.pid)", kind: .claude, cwd: agent.cwd, branch: "",
                            title: "Live session", filePath: "", modified: Date(),
                            state: .working, activity: "Running…", model: "", contextTokens: 0,
                            prNumber: nil, prRepo: nil, prURL: nil, worktree: isWorktree(agent.cwd))
    }

    static func codexSession(for agent: RunningAgent, root: String) -> AgentSession {
        AgentSession(id: agent.uuid ?? "codex-\(agent.pid)", kind: .codex, cwd: agent.cwd, branch: "",
                     title: URL(fileURLWithPath: agent.cwd).lastPathComponent, filePath: "",
                     modified: Date(), state: .working, activity: "Codex is running", model: "codex",
                     contextTokens: 0, prNumber: nil, prRepo: nil, prURL: nil, worktree: isWorktree(agent.cwd))
    }

    static func newestJSONL(_ dir: URL) -> URL? {
        let manager = FileManager.default
        guard let items = try? manager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        return items.filter { $0.pathExtension == "jsonl" }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    static func isWorktree(_ cwd: String) -> Bool {
        guard !cwd.isEmpty else { return false }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd + "/.git", isDirectory: &isDir) else { return false }
        return !isDir.boolValue
    }

    static func head(_ url: URL, bytes: Int = 16384) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: bytes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func tail(_ url: URL, bytes: UInt64 = 131072) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > bytes ? size - bytes : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func object(_ line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func text(from content: Any?) -> String {
        if let string = content as? String { return string }
        if let blocks = content as? [[String: Any]] {
            for block in blocks where block["type"] as? String == "text" {
                if let value = block["text"] as? String { return value }
            }
        }
        return ""
    }

    static func toolName(from content: Any?) -> String? {
        guard let blocks = content as? [[String: Any]] else { return nil }
        for block in blocks where block["type"] as? String == "tool_use" { return block["name"] as? String }
        return nil
    }

    static func parseClaude(_ url: URL, _ date: Date, cwd: String) -> AgentSession {
        var branch = "", title = ""
        for line in head(url).split(separator: "\n").prefix(150) {
            guard let obj = object(line) else { continue }
            if branch.isEmpty, let value = obj["gitBranch"] as? String, !value.isEmpty { branch = value }
            if title.isEmpty, obj["type"] as? String == "user", let message = obj["message"] as? [String: Any] {
                title = text(from: message["content"])
            }
            if !branch.isEmpty && !title.isEmpty { break }
        }

        var model = "", stop = "", lastAssistant = "", lastTool = "", lastConv = ""
        var context = 0
        var prNumber: Int?, prRepo: String?, prURL: String?
        for line in tail(url).split(separator: "\n") {
            guard let obj = object(line) else { continue }
            switch obj["type"] as? String {
            case "pr-link":
                prNumber = obj["prNumber"] as? Int
                prRepo = obj["prRepository"] as? String
                prURL = obj["prUrl"] as? String
            case "assistant":
                lastConv = "assistant"
                if let message = obj["message"] as? [String: Any] {
                    if let value = message["model"] as? String { model = value }
                    stop = message["stop_reason"] as? String ?? ""
                    if let usage = message["usage"] as? [String: Any] {
                        context = (usage["input_tokens"] as? Int ?? 0)
                            + (usage["cache_read_input_tokens"] as? Int ?? 0)
                            + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                    }
                    let value = text(from: message["content"])
                    if !value.isEmpty { lastAssistant = value }
                    if let tool = toolName(from: message["content"]) { lastTool = tool }
                }
            case "user":
                lastConv = "user"
            default:
                break
            }
        }

        let live = Date().timeIntervalSince(date) < 25
        let state: AgentSession.State
        if live && lastConv != "assistant" { state = .working }
        else if lastConv == "assistant" && stop == "end_turn" { state = .waiting }
        else if live { state = .working }
        else { state = .idle }

        let activity: String
        switch state {
        case .waiting: activity = lastAssistant.isEmpty ? "Waiting for your reply" : lastAssistant
        case .working: activity = lastTool.isEmpty ? "Working…" : "Using \(lastTool)…"
        case .idle: activity = lastAssistant.isEmpty ? "Idle" : lastAssistant
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return AgentSession(
            id: url.deletingPathExtension().lastPathComponent, kind: .claude,
            cwd: cwd, branch: branch,
            title: cleanTitle.isEmpty ? "Untitled session" : String(cleanTitle.prefix(100)),
            filePath: url.path, modified: date, state: state,
            activity: String(activity.prefix(280)), model: model, contextTokens: context,
            prNumber: prNumber, prRepo: prRepo, prURL: prURL, worktree: isWorktree(cwd))
    }
}
