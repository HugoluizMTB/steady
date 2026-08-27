import Foundation

/// UserDefaults-backed preferences. All values have sane defaults so a fresh
/// install behaves like the original app plus data tracking.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            Key.showAllProcesses: false,
            Key.refreshInterval: 3.0,
            Key.showUsageInMenuBar: true,
            Key.confirmKill: true,
            Key.notifyNewPorts: false,
            Key.trackAllNetworks: true,
            Key.monthlyCapGB: 0.0,
            Key.billingCycleDay: 1,
            Key.warnOnCap: true,
        ])
    }

    private enum Key {
        static let showAllProcesses = "showAllProcesses"
        static let refreshInterval = "refreshInterval"
        static let showUsageInMenuBar = "showUsageInMenuBar"
        static let confirmKill = "confirmKill"
        static let notifyNewPorts = "notifyNewPorts"
        static let trackAllNetworks = "trackAllNetworks"
        static let monthlyCapGB = "monthlyCapGB"
        static let billingCycleDay = "billingCycleDay"
        static let warnOnCap = "warnOnCap"
    }

    var showAllProcesses: Bool {
        get { d.bool(forKey: Key.showAllProcesses) }
        set { d.set(newValue, forKey: Key.showAllProcesses) }
    }
    var refreshInterval: TimeInterval {
        get { max(1, d.double(forKey: Key.refreshInterval)) }
        set { d.set(newValue, forKey: Key.refreshInterval) }
    }
    var showUsageInMenuBar: Bool {
        get { d.bool(forKey: Key.showUsageInMenuBar) }
        set { d.set(newValue, forKey: Key.showUsageInMenuBar) }
    }
    var confirmKill: Bool {
        get { d.bool(forKey: Key.confirmKill) }
        set { d.set(newValue, forKey: Key.confirmKill) }
    }
    var notifyNewPorts: Bool {
        get { d.bool(forKey: Key.notifyNewPorts) }
        set { d.set(newValue, forKey: Key.notifyNewPorts) }
    }
    /// Also accumulate per-day totals for regular Wi-Fi/Ethernet (shown separately).
    var trackAllNetworks: Bool {
        get { d.bool(forKey: Key.trackAllNetworks) }
        set { d.set(newValue, forKey: Key.trackAllNetworks) }
    }
    /// 0 means "no cap".
    var monthlyCapGB: Double {
        get { max(0, d.double(forKey: Key.monthlyCapGB)) }
        set { d.set(max(0, newValue), forKey: Key.monthlyCapGB) }
    }
    var monthlyCapBytes: UInt64 { UInt64(monthlyCapGB * 1_000_000_000) }
    /// Day of month the mobile plan resets (1...28).
    var billingCycleDay: Int {
        get { min(max(d.integer(forKey: Key.billingCycleDay), 1), 28) }
        set { d.set(min(max(newValue, 1), 28), forKey: Key.billingCycleDay) }
    }
    var warnOnCap: Bool {
        get { d.bool(forKey: Key.warnOnCap) }
        set { d.set(newValue, forKey: Key.warnOnCap) }
    }
}
