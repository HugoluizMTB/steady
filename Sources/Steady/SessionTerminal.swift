import SwiftUI
import AppKit
import SwiftTerm

struct SessionTerminal: NSViewRepresentable {
    let session: AgentSession

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 720, height: 480))
        terminal.nativeBackgroundColor = NSColor(red: 0.03, green: 0.04, blue: 0.05, alpha: 1)
        terminal.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["LANG"] = environment["LANG"] ?? "en_US.UTF-8"
        let environmentArray = environment.map { "\($0.key)=\($0.value)" }

        terminal.startProcess(executable: "/bin/zsh", args: ["-lc", command()], environment: environmentArray)
        return terminal
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    private func command() -> String {
        let cwd = session.cwd.isEmpty ? NSHomeDirectory() : session.cwd
        let name = "steady_" + session.id.replacingOccurrences(of: "-", with: "").prefix(24)

        let agent: String
        if session.kind == .claude {
            agent = "CLAUDE_CONFIG_DIR=\(quote(session.profile.root)) claude --resume \(quote(session.id))"
        } else {
            agent = "CODEX_HOME=\(quote(session.profile.root)) codex resume \(quote(session.id))"
        }

        let inner = "cd \(quote(cwd)); \(agent)"
        return "if command -v tmux >/dev/null 2>&1; then exec tmux new-session -A -s \(name) \(quote(inner)); else \(inner); fi"
    }

    private func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
