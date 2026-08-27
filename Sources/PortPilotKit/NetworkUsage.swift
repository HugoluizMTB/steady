import Foundation
import Network
#if canImport(CoreWLAN)
import CoreWLAN
#endif

struct DayUsage: Codable {
    var inBytes: UInt64 = 0
    var outBytes: UInt64 = 0
    var total: UInt64 { inBytes &+ outBytes }
}

/// Tracks bytes moved over the primary network interface and splits them into
/// "metered" (iPhone Personal Hotspot / cellular) and "unmetered" buckets.
///
/// Byte counts come from the kernel interface counters (`NET_RT_IFLIST2`, the
/// same source as `netstat -ib`), so they cover every app on the Mac — not just
/// traffic Port Pilot can see. macOS reports a Personal Hotspot link as an
/// expensive path, which is what flags a session as metered.
final class UsageMonitor {
    static let shared = UsageMonitor()

    // MARK: Live state (main thread only)

    private(set) var isMetered = false
    private(set) var isConstrained = false
    private(set) var pathSatisfied = false
    private(set) var primaryInterface: String?
    private(set) var primaryType: NWInterface.InterfaceType?

    private(set) var sessionIn: UInt64 = 0
    private(set) var sessionOut: UInt64 = 0
    private(set) var sessionStart: Date?
    private(set) var lastSessionTotal: UInt64 = 0
    private(set) var lastSessionEnded: Date?

    private(set) var downRate: Double = 0
    private(set) var upRate: Double = 0

    /// Called on the main thread after every sample and on path changes.
    var onChange: (() -> Void)?

    // MARK: Persisted

    private var meteredDays: [String: DayUsage] = [:]
    private var otherDays: [String: DayUsage] = [:]
    private var firedAlerts: Set<String> = []

    // MARK: Internals

    private let monitor = NWPathMonitor()
    private var sampleTimer: Timer?
    private var lastCounters: (inBytes: UInt64, outBytes: UInt64)?
    private var lastCounterInterface: String?
    private var lastSampleAt: Date?
    private var dirty = false
    private var lastSaveAt = Date()

    /// A single 2 s sample can't plausibly carry more than this; a bigger jump
    /// means the interface counters were reset, so the sample is dropped.
    private let sanityLimitPerSample: UInt64 = 2_000_000_000

    private init() {
        load()
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.apply(path: path) }
        }
        monitor.start(queue: DispatchQueue(label: "com.portpilot.path"))

        sampleTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.sample()
        }
        sampleTimer?.tolerance = 0.5
    }

    // MARK: - Path

    private func apply(path: NWPath) {
        pathSatisfied = path.status == .satisfied
        isConstrained = path.isConstrained

        // Prefer the physical uplink; a VPN tunnel would double-count bytes.
        let ranked: [NWInterface.InterfaceType] = [.cellular, .wifi, .wiredEthernet]
        let iface = ranked.compactMap { type in
            path.availableInterfaces.first { $0.type == type }
        }.first ?? path.availableInterfaces.first

        let wasMetered = isMetered
        let previousInterface = primaryInterface

        primaryInterface = iface?.name
        primaryType = iface?.type
        isMetered = path.isExpensive || iface?.type == .cellular

        if primaryInterface != previousInterface {
            // New link: rebaseline instead of attributing its lifetime counters.
            lastCounters = nil
            lastCounterInterface = primaryInterface
        }

        if isMetered && !wasMetered {
            beginSession()
        } else if !isMetered && wasMetered {
            endSession()
        }

        onChange?()
    }

    private func beginSession() {
        sessionIn = 0
        sessionOut = 0
        sessionStart = Date()
        downRate = 0
        upRate = 0
        dirty = true
    }

    private func endSession() {
        lastSessionTotal = sessionTotal
        lastSessionEnded = Date()
        sessionStart = nil
        downRate = 0
        upRate = 0
        save()
    }

    // MARK: - Sampling

    private func sample() {
        guard let iface = primaryInterface,
              let counters = Self.interfaceCounters()[iface] else { return }

        let now = Date()
        defer {
            lastCounters = counters
            lastCounterInterface = iface
            lastSampleAt = now
        }

        guard lastCounterInterface == iface, let previous = lastCounters else { return }

        // Counters are monotonic 64-bit values; a decrease means a reset.
        guard counters.inBytes >= previous.inBytes, counters.outBytes >= previous.outBytes else { return }
        let deltaIn = counters.inBytes - previous.inBytes
        let deltaOut = counters.outBytes - previous.outBytes
        guard deltaIn < sanityLimitPerSample, deltaOut < sanityLimitPerSample else { return }

        let elapsed = lastSampleAt.map { now.timeIntervalSince($0) } ?? 2
        if elapsed > 0 {
            let alpha = 0.4
            downRate = downRate * (1 - alpha) + (Double(deltaIn) / elapsed) * alpha
            upRate = upRate * (1 - alpha) + (Double(deltaOut) / elapsed) * alpha
        }

        if deltaIn == 0 && deltaOut == 0 {
            onChange?()
            return
        }

        let key = Fmt.dayKey(now)
        if isMetered {
            sessionIn &+= deltaIn
            sessionOut &+= deltaOut
            var day = meteredDays[key] ?? DayUsage()
            day.inBytes &+= deltaIn
            day.outBytes &+= deltaOut
            meteredDays[key] = day
            checkCapAlerts()
        } else if Settings.shared.trackAllNetworks {
            var day = otherDays[key] ?? DayUsage()
            day.inBytes &+= deltaIn
            day.outBytes &+= deltaOut
            otherDays[key] = day
        }

        dirty = true
        if now.timeIntervalSince(lastSaveAt) > 20 { save() }
        onChange?()
    }

    /// Per-interface 64-bit byte counters from the routing socket.
    static func interfaceCounters() -> [String: (inBytes: UInt64, outBytes: UInt64)] {
        var result: [String: (inBytes: UInt64, outBytes: UInt64)] = [:]
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return result }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return result }

        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }

                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size + MemoryLayout<sockaddr_dl>.size <= length {
                    let message = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    let sdl = raw.loadUnaligned(fromByteOffset: offset + MemoryLayout<if_msghdr2>.size,
                                                as: sockaddr_dl.self)
                    let nameLength = Int(sdl.sdl_nlen)
                    if nameLength > 0 {
                        var bytes: [UInt8] = []
                        withUnsafeBytes(of: sdl.sdl_data) { chars in
                            for i in 0..<min(nameLength, chars.count) { bytes.append(chars[i]) }
                        }
                        let name = String(decoding: bytes, as: UTF8.self)
                        result[name] = (UInt64(message.ifm_data.ifi_ibytes),
                                        UInt64(message.ifm_data.ifi_obytes))
                    }
                }
                offset += messageLength
            }
        }
        return result
    }

    // MARK: - Queries

    var sessionTotal: UInt64 { sessionIn &+ sessionOut }
    var sessionDuration: TimeInterval { sessionStart.map { Date().timeIntervalSince($0) } ?? 0 }

    var todayMetered: DayUsage { meteredDays[Fmt.dayKey(Date())] ?? DayUsage() }
    var todayOther: DayUsage { otherDays[Fmt.dayKey(Date())] ?? DayUsage() }

    /// Start of the current billing cycle, based on the configured reset day.
    var cycleStart: Date {
        let calendar = Calendar.current
        let now = Date()
        let day = Settings.shared.billingCycleDay
        var components = calendar.dateComponents([.year, .month], from: now)
        components.day = day
        let candidate = calendar.date(from: components) ?? now
        if candidate <= now { return calendar.startOfDay(for: candidate) }
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: candidate) ?? candidate
        return calendar.startOfDay(for: previousMonth)
    }

    var cycleUsage: DayUsage {
        let start = Fmt.dayKey(cycleStart)
        var total = DayUsage()
        for (key, day) in meteredDays where key >= start {
            total.inBytes &+= day.inBytes
            total.outBytes &+= day.outBytes
        }
        return total
    }

    var cycleFraction: Double? {
        let cap = Settings.shared.monthlyCapBytes
        guard cap > 0 else { return nil }
        return Double(cycleUsage.total) / Double(cap)
    }

    /// Metered usage for the last `count` days, newest first.
    func recentDays(_ count: Int) -> [(key: String, usage: DayUsage)] {
        let calendar = Calendar.current
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = Fmt.dayKey(date)
            return (key, meteredDays[key] ?? DayUsage())
        }
    }

    /// Human label for the current link, e.g. "iPhone Hotspot" or "Wi-Fi".
    var networkLabel: String {
        guard pathSatisfied else { return "Offline" }
        if isMetered {
            if let ssid = Self.currentSSID() { return ssid }
            return primaryType == .cellular ? "Cellular" : "Personal Hotspot"
        }
        switch primaryType {
        case .wifi: return Self.currentSSID() ?? "Wi-Fi"
        case .wiredEthernet: return "Ethernet"
        case .cellular: return "Cellular"
        default: return primaryInterface ?? "Network"
        }
    }

    /// The SSID is only available when the user has granted Location Services
    /// access; a nil result just means we fall back to a generic label.
    static func currentSSID() -> String? {
        #if canImport(CoreWLAN)
        guard let ssid = CWWiFiClient.shared().interface()?.ssid(), !ssid.isEmpty else { return nil }
        return ssid
        #else
        return nil
        #endif
    }

    // MARK: - Actions

    func resetSession() {
        beginSession()
        onChange?()
    }

    func resetCycle() {
        let start = Fmt.dayKey(cycleStart)
        meteredDays = meteredDays.filter { $0.key < start }
        firedAlerts.removeAll()
        save()
        onChange?()
    }

    func resetAllHistory() {
        meteredDays.removeAll()
        otherDays.removeAll()
        firedAlerts.removeAll()
        sessionIn = 0
        sessionOut = 0
        save()
        onChange?()
    }

    private func checkCapAlerts() {
        guard Settings.shared.warnOnCap, let fraction = cycleFraction else { return }
        let cycleKey = Fmt.dayKey(cycleStart)
        for threshold in [0.5, 0.8, 1.0] where fraction >= threshold {
            let alertKey = "\(cycleKey):\(Int(threshold * 100))"
            guard !firedAlerts.contains(alertKey) else { continue }
            firedAlerts.insert(alertKey)
            dirty = true
            let percent = Int(threshold * 100)
            Notifier.post(
                title: threshold >= 1 ? "Mobile data cap reached" : "\(percent)% of mobile data used",
                body: "\(Fmt.bytes(cycleUsage.total)) of \(Fmt.bytes(Settings.shared.monthlyCapBytes)) this cycle."
            )
        }
    }

    // MARK: - Persistence

    private struct Store: Codable {
        var meteredDays: [String: DayUsage] = [:]
        var otherDays: [String: DayUsage] = [:]
        var firedAlerts: [String] = []
        var sessionIn: UInt64 = 0
        var sessionOut: UInt64 = 0
        var sessionStart: Date?
        var lastSessionTotal: UInt64 = 0
        var lastSessionEnded: Date?
    }

    private var storeURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("PortPilot")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("usage.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let store = try? JSONDecoder().decode(Store.self, from: data) else { return }
        meteredDays = store.meteredDays
        otherDays = store.otherDays
        firedAlerts = Set(store.firedAlerts)
        lastSessionTotal = store.lastSessionTotal
        lastSessionEnded = store.lastSessionEnded
        // Keep a session that was in progress when the app quit, if it's recent.
        if let start = store.sessionStart, Date().timeIntervalSince(start) < 86_400 {
            sessionStart = start
            sessionIn = store.sessionIn
            sessionOut = store.sessionOut
        }
    }

    func save() {
        guard dirty else { return }
        prune()
        let store = Store(meteredDays: meteredDays,
                          otherDays: otherDays,
                          firedAlerts: Array(firedAlerts),
                          sessionIn: sessionIn,
                          sessionOut: sessionOut,
                          sessionStart: sessionStart,
                          lastSessionTotal: lastSessionTotal,
                          lastSessionEnded: lastSessionEnded)
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: storeURL, options: .atomic)
        }
        dirty = false
        lastSaveAt = Date()
    }

    private func prune() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -400, to: Date()) else { return }
        let key = Fmt.dayKey(cutoff)
        meteredDays = meteredDays.filter { $0.key >= key }
        otherDays = otherDays.filter { $0.key >= key }
    }
}
