import Foundation

enum Fmt {
    /// Carrier-style decimal bytes (1 GB = 1000 MB), e.g. "1.24 GB".
    static func bytes(_ b: UInt64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .decimal
        f.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return f.string(fromByteCount: Int64(clamping: b))
    }

    /// Tight form for the menu bar, e.g. "1.2GB".
    static func compact(_ b: UInt64) -> String {
        let v = Double(b)
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
        for (scale, suffix) in units where v >= scale {
            let n = v / scale
            return n >= 10 ? "\(Int(n.rounded()))\(suffix)" : String(format: "%.1f%@", n, suffix)
        }
        return "\(b)B"
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond >= 1 else { return "0 KB/s" }
        return compact(UInt64(bytesPerSecond)) + "/s"
    }

    static func duration(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        let d = s / 86_400, h = (s % 86_400) / 3_600, m = (s % 3_600) / 60, sec = s % 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(sec)s" }
        return "\(sec)s"
    }

    /// Text progress bar, e.g. "▰▰▰▰▱▱▱▱▱▱".
    static func rawBar(_ fraction: Double, width: Int = 10) -> String {
        let clamped = min(max(fraction, 0), 1)
        let filled = Int((clamped * Double(width)).rounded())
        return String(repeating: "▰", count: filled) + String(repeating: "▱", count: width - filled)
    }

    /// Progress bar with its percentage, e.g. "▰▰▰▰▱▱▱▱▱▱  41%".
    static func bar(_ fraction: Double, width: Int = 10) -> String {
        rawBar(fraction, width: width) + "  \(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// Pads to a fixed width so monospaced menu rows line up.
    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date) -> String { dayKeyFormatter.string(from: date) }

    static func shortDay(_ key: String) -> String {
        guard let date = dayKeyFormatter.date(from: key) else { return key }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }
}
