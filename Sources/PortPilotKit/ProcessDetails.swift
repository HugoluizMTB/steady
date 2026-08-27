import Foundation

/// Extra context for a listening process: where it runs from, how long it has
/// been up, and what it costs. Fetched lazily when a submenu opens and cached
/// briefly so repeated menu opens stay cheap.
struct ProcessDetails {
    var cwd: String?
    var commandLine: String?
    var cpuPercent: Double?
    var memoryBytes: UInt64?
    var uptime: TimeInterval?

    var projectName: String? {
        guard let cwd, cwd != "/" else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

enum ProcessInspector {
    private static var cache: [Int32: (details: ProcessDetails, at: Date)] = [:]
    private static let ttl: TimeInterval = 4

    static func details(for pid: Int32) -> ProcessDetails {
        if let hit = cache[pid], Date().timeIntervalSince(hit.at) < ttl {
            return hit.details
        }
        var result = ProcessDetails()

        // %cpu, rss (KB), elapsed time, then the full command line (may contain spaces).
        if let out = PortScanner.shell("/bin/ps", ["-p", "\(pid)", "-o", "%cpu=,rss=,etime=,command="]),
           let line = out.split(separator: "\n").first {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if fields.count >= 4 {
                result.cpuPercent = Double(fields[0])
                if let rss = UInt64(fields[1]) { result.memoryBytes = rss * 1024 }
                result.uptime = parseETime(String(fields[2]))
                result.commandLine = fields[3...].joined(separator: " ")
            }
        }

        if let out = PortScanner.shell("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]) {
            for line in out.split(separator: "\n") where line.hasPrefix("n") {
                result.cwd = String(line.dropFirst())
                break
            }
        }

        cache[pid] = (result, Date())
        return result
    }

    static func invalidate() { cache.removeAll() }

    /// `ps` elapsed time comes as `[[dd-]hh:]mm:ss`.
    static func parseETime(_ raw: String) -> TimeInterval? {
        var days = 0.0
        var rest = raw
        if let dash = raw.firstIndex(of: "-") {
            days = Double(raw[raw.startIndex..<dash]) ?? 0
            rest = String(raw[raw.index(after: dash)...])
        }
        let parts = rest.split(separator: ":").compactMap { Double($0) }
        guard !parts.isEmpty else { return nil }
        let seconds = parts.reduce(0.0) { $0 * 60 + $1 }
        return days * 86_400 + seconds
    }

    /// PIDs of every descendant of `pid`, deepest last.
    static func descendants(of pid: Int32) -> [Int32] {
        guard let out = PortScanner.shell("/usr/bin/pgrep", ["-P", "\(pid)"]) else { return [] }
        let children = out.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        return children + children.flatMap { descendants(of: $0) }
    }
}
