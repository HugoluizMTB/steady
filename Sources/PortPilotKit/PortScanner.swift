import Foundation

struct PortInfo: Equatable, Hashable {
    let port: UInt16
    let pid: Int32
    let command: String
    let user: String
    /// True when bound to loopback only (127.0.0.1 / ::1).
    let loopbackOnly: Bool
}

/// Scans listening TCP ports with `lsof`, off the main thread.
final class PortScanner {
    static let shared = PortScanner()

    private let queue = DispatchQueue(label: "com.portpilot.scanner", qos: .utility)
    private var scanning = false

    private(set) var ports: [PortInfo] = []
    private(set) var lastScan: Date?

    /// Commands treated as development servers when "show all" is off.
    /// Matched as a case-insensitive prefix of the process name.
    private static let devPrefixes: [String] = [
        "node", "deno", "bun", "npm", "yarn", "pnpm", "next", "vite", "esbuild",
        "webpack", "nuxt", "astro", "remix", "ng", "electron",
        "python", "uvicorn", "gunicorn", "hypercorn", "flask", "celery", "django",
        "ruby", "rails", "puma", "unicorn", "sidekiq", "jekyll",
        "php", "artisan", "java", "gradle", "kotlin", "scala", "sbt",
        "go", "air", "hugo", "dotnet", "cargo", "rustc", "elixir", "beam", "erl",
        "docker", "com.docker", "colima", "qemu", "containerd",
        "postgres", "mysqld", "mariadb", "mongod", "redis-server", "memcached",
        "nginx", "caddy", "httpd", "traefik", "ngrok", "cloudflared", "localtunnel",
        "http-server", "serve", "browser-sync", "ollama", "supabase", "firebase",
        "wrangler", "expo", "metro", "rustrover", "jupyter", "streamlit", "grafana",
    ]

    static func isDevCommand(_ command: String) -> Bool {
        let lower = command.lowercased()
        return devPrefixes.contains { lower.hasPrefix($0) }
    }

    /// Kicks off a background scan; the completion runs on the main queue only
    /// when the result differs from the previous one.
    func scan(onChange: @escaping ([PortInfo]) -> Void) {
        queue.async { [weak self] in
            guard let self, !self.scanning else { return }
            self.scanning = true
            let found = Self.runLsof()
            self.scanning = false
            DispatchQueue.main.async {
                let changed = found != self.ports
                self.ports = found
                self.lastScan = Date()
                if changed { onChange(found) }
            }
        }
    }

    /// Applies the current visibility filter. Named ports are always shown.
    func visiblePorts(names: [UInt16: String]) -> [PortInfo] {
        guard !Settings.shared.showAllProcesses else { return ports }
        return ports.filter { Self.isDevCommand($0.command) || names[$0.port] != nil }
    }

    // MARK: - lsof

    /// `-F` field output is used instead of column splitting because process
    /// names can contain spaces (e.g. "Canva Helper").
    private static func runLsof() -> [PortInfo] {
        guard let output = shell("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcLn"]) else {
            return []
        }

        var results: [PortInfo] = []
        var seen = Set<String>()
        var pid: Int32 = 0
        var command = ""
        var user = ""

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())

            switch tag {
            case "p": pid = Int32(value) ?? 0
            case "c": command = value
            case "L": user = value
            case "n":
                guard pid != 0,
                      let colon = value.lastIndex(of: ":"),
                      let port = UInt16(value[value.index(after: colon)...]) else { continue }
                let host = String(value[value.startIndex..<colon])
                let key = "\(pid):\(port)"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                let loopback = host == "127.0.0.1" || host == "[::1]" || host == "localhost"
                results.append(PortInfo(port: port, pid: pid, command: command,
                                        user: user, loopbackOnly: loopback))
            default: break
            }
        }

        return results.sorted { $0.port == $1.port ? $0.pid < $1.pid : $0.port < $1.port }
    }

    @discardableResult
    static func shell(_ path: String, _ arguments: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
