import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu!
    private var refreshTimer: Timer?
    private var currentInterval: TimeInterval = 0
    private var menuIsOpen = false
    private var knownPorts: Set<UInt16> = []
    private var currentSymbol = ""

    /// Submenu delegates must be retained for as long as the menu is on screen.
    private var retainedDelegates: [NSMenuDelegate] = []
    /// Items whose titles are recomputed while the menu stays open.
    private var liveItems: [(item: NSMenuItem, render: (NSMenuItem) -> Void)] = []

    var portNames: [UInt16: String] = [:] {
        didSet { savePortNames() }
    }

    // MARK: - Lifecycle

    override init() {
        super.init()
    }

    func attach() -> NSMenu {
        loadPortNames()
        Notifier.requestAuthorization()

        let created = NSMenu()
        created.delegate = self
        menu = created

        UsageMonitor.shared.onChange = { [weak self] in
            self?.updateStatusItem()
            self?.refreshLiveItems()
        }
        UsageMonitor.shared.start()

        restartTimer()
        rescan()
        return created
    }

    func save() {
        UsageMonitor.shared.save()
    }

    private func restartTimer() {
        let interval = Settings.shared.refreshInterval
        guard interval != currentInterval else { return }
        currentInterval = interval
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.rescan()
        }
        refreshTimer?.tolerance = interval / 3
    }

    private func rescan() {
        PortScanner.shared.scan { [weak self] _ in
            self?.handleScanChange()
        }
    }

    private func handleScanChange() {
        let ports = PortScanner.shared.visiblePorts(names: portNames)
        let current = Set(ports.map(\.port))

        if Settings.shared.notifyNewPorts, !knownPorts.isEmpty {
            for port in current.subtracting(knownPorts).sorted() {
                let info = ports.first { $0.port == port }
                Notifier.post(title: "New port \(port)",
                              body: portNames[port] ?? info?.command ?? "A process started listening.")
            }
        }
        knownPorts = current
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let usage = UsageMonitor.shared
        let count = PortScanner.shared.visiblePorts(names: portNames).count

        let symbol = usage.isMetered ? "personalhotspot" : "network"
        if currentSymbol != symbol {
            currentSymbol = symbol
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Port Pilot")
        }

        var parts: [String] = []
        if count > 0 { parts.append("\(count)") }
        if usage.isMetered, Settings.shared.showUsageInMenuBar {
            parts.append(Fmt.compact(usage.sessionTotal))
        }
        button.title = parts.isEmpty ? "" : " " + parts.joined(separator: "  ")
    }

    // MARK: - Main menu

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menuIsOpen = true
        rescan()
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menuIsOpen = false
        liveItems.removeAll()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menu.removeAllItems()
        retainedDelegates.removeAll()
        liveItems.removeAll()
        ProcessInspector.invalidate()

        buildUsageSection(in: menu)
        buildPortSection(in: menu)

        menu.addItem(.separator())
        let settings = LazyMenuDelegate { [weak self] submenu in self?.buildSettings(in: submenu) }
        retainedDelegates.append(settings)
        menu.addSubmenu("Settings", symbol: "gearshape", delegate: settings)

        menu.addAction("Refresh", symbol: "arrow.clockwise", key: "r", target: self, action: #selector(refreshNow))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Port Pilot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
    }

    // MARK: - Usage section

    private func buildUsageSection(in menu: NSMenu) {
        let usage = UsageMonitor.shared
        guard usage.pathSatisfied else {
            menu.addInfo("Offline")
            menu.addItem(.separator())
            return
        }

        let details = LazyMenuDelegate { [weak self] submenu in self?.buildUsageDetails(in: submenu) }
        retainedDelegates.append(details)

        if usage.isMetered {
            menu.addInfo("\(usage.networkLabel)  ·  metered", weight: .medium)
            let item = menu.addSubmenu("", symbol: "personalhotspot", delegate: details)
            let render: (NSMenuItem) -> Void = { menuItem in
                let monitor = UsageMonitor.shared
                var detail = "↓ \(Fmt.bytes(monitor.sessionIn))   ↑ \(Fmt.bytes(monitor.sessionOut))"
                if monitor.sessionStart != nil {
                    detail += "  ·  \(Fmt.duration(monitor.sessionDuration))"
                }
                if monitor.downRate > 1024 || monitor.upRate > 1024 {
                    detail += "  ·  \(Fmt.rate(monitor.downRate))"
                }
                menuItem.attributedTitle = MenuStyle.stacked(
                    "\(Fmt.bytes(monitor.sessionTotal)) this session", detail)
            }
            render(item)
            liveItems.append((item, render))

            if usage.cycleFraction != nil {
                let capItem = menu.addInfo("", size: 10)
                let renderCap: (NSMenuItem) -> Void = { menuItem in
                    let monitor = UsageMonitor.shared
                    let text = "\(Fmt.bar(monitor.cycleFraction ?? 0))  of \(Fmt.bytes(Settings.shared.monthlyCapBytes)) this cycle"
                    let overCap = (monitor.cycleFraction ?? 0) >= 1
                    menuItem.attributedTitle = NSAttributedString(string: text, attributes: [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
                        .foregroundColor: overCap ? NSColor.systemRed : NSColor.secondaryLabelColor,
                    ])
                }
                renderCap(capItem)
                liveItems.append((capItem, renderCap))
            } else {
                let todayItem = menu.addInfo("", size: 10)
                let renderToday: (NSMenuItem) -> Void = { menuItem in
                    let monitor = UsageMonitor.shared
                    menuItem.attributedTitle = NSAttributedString(
                        string: "\(Fmt.bytes(monitor.todayMetered.total)) today  ·  \(Fmt.bytes(monitor.cycleUsage.total)) this cycle",
                        attributes: [
                            .font: NSFont.systemFont(ofSize: 10),
                            .foregroundColor: NSColor.secondaryLabelColor,
                        ])
                }
                renderToday(todayItem)
                liveItems.append((todayItem, renderToday))
            }
        } else {
            let item = menu.addSubmenu("", symbol: "wifi", delegate: details)
            item.attributedTitle = MenuStyle.stacked(
                "Data Usage",
                "\(usage.networkLabel) · not metered · \(Fmt.bytes(usage.cycleUsage.total)) mobile this cycle")
        }

        menu.addItem(.separator())
    }

    private func buildUsageDetails(in menu: NSMenu) {
        let usage = UsageMonitor.shared

        menu.addInfo("Mobile data — \(usage.networkLabel)", weight: .medium)
        menu.addItem(.separator())

        if usage.sessionStart != nil || usage.sessionTotal > 0 {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = MenuStyle.stacked(
                "Session   \(Fmt.bytes(usage.sessionTotal))",
                "↓ \(Fmt.bytes(usage.sessionIn))   ↑ \(Fmt.bytes(usage.sessionOut))   ·   \(Fmt.duration(usage.sessionDuration))")
            menu.addItem(item)
        } else {
            menu.addInfo("No hotspot session yet")
        }

        menu.addInfo("Today   \(Fmt.bytes(usage.todayMetered.total))", size: 12, color: .labelColor)
        menu.addInfo("This cycle   \(Fmt.bytes(usage.cycleUsage.total))", size: 12, color: .labelColor)

        if let fraction = usage.cycleFraction {
            let text = "\(Fmt.bar(fraction))  of \(Fmt.bytes(Settings.shared.monthlyCapBytes))"
            let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: fraction >= 1 ? NSColor.systemRed : NSColor.secondaryLabelColor,
            ])
            menu.addItem(item)
            if fraction < 1 {
                let left = Settings.shared.monthlyCapBytes - min(usage.cycleUsage.total, Settings.shared.monthlyCapBytes)
                menu.addInfo("\(Fmt.bytes(left)) left", size: 10)
            }
        } else {
            menu.addInfo("No monthly cap set", size: 10)
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        menu.addInfo("Cycle started \(formatter.string(from: usage.cycleStart))", size: 10)

        if Settings.shared.trackAllNetworks {
            menu.addItem(.separator())
            menu.addInfo("Wi-Fi/Ethernet today   \(Fmt.bytes(usage.todayOther.total))", size: 10)
        }

        menu.addItem(.separator())
        let history = LazyMenuDelegate { [weak self] submenu in self?.buildHistory(in: submenu) }
        retainedDelegates.append(history)
        menu.addSubmenu("Last 14 Days", symbol: "calendar", delegate: history)

        menu.addItem(.separator())
        menu.addAction("Set Monthly Cap…", symbol: "gauge.with.dots.needle.33percent",
                       target: self, action: #selector(setMonthlyCap))
        menu.addAction("Set Cycle Reset Day…", symbol: "calendar.badge.clock",
                       target: self, action: #selector(setCycleDay))
        menu.addItem(.separator())
        menu.addAction("Reset Session Counter", symbol: "arrow.counterclockwise",
                       target: self, action: #selector(resetSession))
        menu.addAction("Reset This Cycle…", symbol: "trash", target: self, action: #selector(resetCycle))
        menu.addAction("Clear All History…", symbol: "trash.slash", target: self, action: #selector(clearHistory))

        if !usage.isMetered {
            menu.addItem(.separator())
            menu.addInfo("Counting starts automatically when you join your iPhone hotspot.", size: 10)
        }
    }

    private func buildHistory(in menu: NSMenu) {
        let days = UsageMonitor.shared.recentDays(14)
        let peak = max(days.map(\.usage.total).max() ?? 0, 1)

        menu.addInfo("Mobile data per day", weight: .medium)
        menu.addItem(.separator())

        for (key, usage) in days {
            let bar = Fmt.rawBar(Double(usage.total) / Double(peak), width: 8)
            let title = "\(Fmt.pad(Fmt.shortDay(key), 12))\(bar)  \(Fmt.bytes(usage.total))"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: usage.total > 0 ? NSColor.labelColor : NSColor.tertiaryLabelColor,
            ])
            menu.addItem(item)
        }

        let total = days.reduce(UInt64(0)) { $0 &+ $1.usage.total }
        menu.addItem(.separator())
        menu.addInfo("14-day total   \(Fmt.bytes(total))", size: 11)
    }

    private func refreshLiveItems() {
        guard menuIsOpen else { return }
        for entry in liveItems { entry.render(entry.item) }
    }

    // MARK: - Ports section

    private func buildPortSection(in menu: NSMenu) {
        let ports = PortScanner.shared.visiblePorts(names: portNames)

        guard !ports.isEmpty else {
            menu.addInfo("No active ports")
            if !Settings.shared.showAllProcesses {
                menu.addInfo("Showing dev servers only", size: 10, color: .tertiaryLabelColor)
            }
            return
        }

        let scope = Settings.shared.showAllProcesses ? "all processes" : "dev servers"
        menu.addInfo("\(ports.count) active port\(ports.count == 1 ? "" : "s")  ·  \(scope)", weight: .medium)
        menu.addItem(.separator())

        for info in ports {
            let name = portNames[info.port]
            let title = ":\(info.port)  \(name ?? info.command)"

            let submenuDelegate = LazyMenuDelegate { [weak self] submenu in
                self?.buildPortSubmenu(in: submenu, info: info)
            }
            retainedDelegates.append(submenuDelegate)

            let item = menu.addSubmenu(title, delegate: submenuDelegate)
            if name != nil {
                item.attributedTitle = MenuStyle.stacked(title, info.command)
            }
            // Green: bound to loopback. Orange: reachable from the network.
            item.image = MenuStyle.dot(info.loopbackOnly ? .systemGreen : .systemOrange, diameter: 8)
        }

        if ports.count > 1 {
            menu.addItem(.separator())
            menu.addAction("Kill All Listed…", symbol: "xmark.octagon", target: self, action: #selector(killAll))
        }
    }

    private func buildPortSubmenu(in menu: NSMenu, info: PortInfo) {
        let details = ProcessInspector.details(for: info.pid)

        menu.addAction("Open in Browser", symbol: "safari", target: self,
                       action: #selector(openPort(_:)), represented: info)
        menu.addAction("Copy URL", symbol: "doc.on.doc", target: self,
                       action: #selector(copyURL(_:)), represented: info)

        menu.addItem(.separator())
        menu.addAction(portNames[info.port] != nil ? "Rename…" : "Set Name…", symbol: "pencil",
                       target: self, action: #selector(setName(_:)), represented: info)
        if portNames[info.port] != nil {
            menu.addAction("Clear Name", symbol: "xmark.circle", target: self,
                           action: #selector(clearName(_:)), represented: info)
        }

        if let cwd = details.cwd, cwd != "/" {
            menu.addItem(.separator())
            menu.addInfo("Project   \(details.projectName ?? cwd)", size: 11, color: .labelColor)
            menu.addAction("Reveal in Finder", symbol: "folder", target: self,
                           action: #selector(revealFolder(_:)), represented: cwd)
            menu.addAction("Open in Terminal", symbol: "terminal", target: self,
                           action: #selector(openTerminal(_:)), represented: cwd)
            if let editor = EditorLauncher.preferred {
                menu.addAction("Open in \(editor.name)", symbol: "chevron.left.forwardslash.chevron.right",
                               target: self, action: #selector(openEditor(_:)), represented: cwd)
            }
            menu.addAction("Copy Path", symbol: "doc.on.clipboard", target: self,
                           action: #selector(copyText(_:)), represented: cwd)
        }

        menu.addItem(.separator())
        var stats = "\(info.command)  ·  PID \(info.pid)"
        if let memory = details.memoryBytes { stats += "  ·  \(Fmt.bytes(memory))" }
        if let cpu = details.cpuPercent { stats += String(format: "  ·  %.1f%% CPU", cpu) }
        if let uptime = details.uptime { stats += "  ·  up \(Fmt.duration(uptime))" }
        menu.addInfo(stats, size: 10, color: .tertiaryLabelColor)
        menu.addInfo(info.loopbackOnly ? "Bound to localhost only" : "Reachable on your network",
                     size: 10, color: .tertiaryLabelColor)

        if let commandLine = details.commandLine {
            menu.addAction("Copy Command Line", symbol: "text.alignleft", target: self,
                           action: #selector(copyText(_:)), represented: commandLine)
        }

        menu.addItem(.separator())
        menu.addAction("Kill Process", symbol: "xmark.octagon", target: self,
                       action: #selector(killPort(_:)), represented: info)
        let children = ProcessInspector.descendants(of: info.pid)
        if !children.isEmpty {
            menu.addAction("Kill Process Tree (\(children.count + 1) processes)", symbol: "xmark.octagon.fill",
                           target: self, action: #selector(killTree(_:)), represented: info)
        }
    }

    // MARK: - Settings menu

    private func buildSettings(in menu: NSMenu) {
        let settings = Settings.shared

        menu.addToggle("Launch at Login", isOn: LoginItem.isEnabled, target: self,
                       action: #selector(toggleLaunchAtLogin))
        menu.addItem(.separator())
        menu.addToggle("Show All Processes", isOn: settings.showAllProcesses, target: self,
                       action: #selector(toggleShowAll))
        menu.addToggle("Show Usage in Menu Bar", isOn: settings.showUsageInMenuBar, target: self,
                       action: #selector(toggleUsageInMenuBar))
        menu.addToggle("Confirm Before Killing", isOn: settings.confirmKill, target: self,
                       action: #selector(toggleConfirmKill))
        menu.addToggle("Notify on New Ports", isOn: settings.notifyNewPorts, target: self,
                       action: #selector(toggleNotifyNewPorts))
        menu.addToggle("Alert Near Data Cap", isOn: settings.warnOnCap, target: self,
                       action: #selector(toggleWarnOnCap))
        menu.addToggle("Track Wi-Fi/Ethernet Too", isOn: settings.trackAllNetworks, target: self,
                       action: #selector(toggleTrackAll))

        menu.addItem(.separator())
        let intervals = LazyMenuDelegate { [weak self] submenu in
            for seconds in [1.0, 2.0, 3.0, 5.0, 10.0] {
                submenu.addToggle("\(Int(seconds)) second\(seconds == 1 ? "" : "s")",
                                  isOn: Settings.shared.refreshInterval == seconds,
                                  target: self, action: #selector(AppDelegate.setInterval(_:)),
                                  represented: seconds)
            }
        }
        retainedDelegates.append(intervals)
        menu.addSubmenu("Scan Interval", symbol: "timer", delegate: intervals)

        menu.addItem(.separator())
        menu.addInfo("Port Pilot \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0")", size: 10)
    }

    // MARK: - Port actions

    @objc private func openPort(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? PortInfo,
              let url = URL(string: "http://localhost:\(info.port)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyURL(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? PortInfo else { return }
        copyToClipboard("http://localhost:\(info.port)")
    }

    @objc private func copyText(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        copyToClipboard(text)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func revealFolder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    @objc private func openTerminal(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.googlecode.iterm2")
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        guard let terminal else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func openEditor(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String, let editor = EditorLauncher.preferred else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: path)], withApplicationAt: editor.url,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func setName(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? PortInfo else { return }

        let alert = NSAlert()
        alert.messageText = "Name for port \(info.port)"
        alert.informativeText = "Process: \(info.command) (PID \(info.pid))"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        input.stringValue = portNames[info.port] ?? ""
        input.placeholderString = "e.g. API Backend, React App…"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            portNames.removeValue(forKey: info.port)
        } else {
            portNames[info.port] = name
        }
        updateStatusItem()
    }

    @objc private func clearName(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? PortInfo else { return }
        portNames.removeValue(forKey: info.port)
    }

    @objc private func killPort(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? PortInfo else { return }
        if Settings.shared.confirmKill {
            guard confirm(title: "Kill process on port \(info.port)?",
                          message: "This will terminate \(info.command) (PID \(info.pid)).",
                          button: "Kill") else { return }
        }
        terminate(pids: [info.pid])
    }

    @objc private func killTree(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? PortInfo else { return }
        let pids = [info.pid] + ProcessInspector.descendants(of: info.pid)
        if Settings.shared.confirmKill {
            guard confirm(title: "Kill \(pids.count) processes?",
                          message: "\(info.command) on port \(info.port) and all of its child processes.",
                          button: "Kill All") else { return }
        }
        terminate(pids: pids)
    }

    @objc private func killAll() {
        let ports = PortScanner.shared.visiblePorts(names: portNames)
        guard !ports.isEmpty else { return }
        guard confirm(title: "Kill \(ports.count) processes?",
                      message: ports.map { ":\($0.port) \($0.command)" }.joined(separator: "\n"),
                      button: "Kill All") else { return }
        terminate(pids: ports.map(\.pid))
    }

    /// SIGTERM first, then SIGKILL for anything still alive a second later.
    func terminate(pids: [Int32]) {
        for pid in pids.reversed() { kill(pid, SIGTERM) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            for pid in pids.reversed() where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            ProcessInspector.invalidate()
            self?.rescan()
        }
    }

    // MARK: - Usage actions

    @objc private func setMonthlyCap() {
        let current = Settings.shared.monthlyCapGB
        guard let value = promptForNumber(
            title: "Monthly mobile data cap",
            message: "Amount in GB that your plan includes each cycle. Use 0 for no cap.",
            initial: current > 0 ? String(format: "%g", current) : "",
            placeholder: "e.g. 20") else { return }
        Settings.shared.monthlyCapGB = value
        updateStatusItem()
    }

    @objc private func setCycleDay() {
        guard let value = promptForNumber(
            title: "Cycle reset day",
            message: "Day of the month your mobile data allowance resets (1–28).",
            initial: "\(Settings.shared.billingCycleDay)",
            placeholder: "1") else { return }
        Settings.shared.billingCycleDay = Int(value)
    }

    @objc private func resetSession() {
        UsageMonitor.shared.resetSession()
        updateStatusItem()
    }

    @objc private func resetCycle() {
        guard confirm(title: "Reset usage for this cycle?",
                      message: "Mobile data recorded since \(Fmt.shortDay(Fmt.dayKey(UsageMonitor.shared.cycleStart))) will be cleared.",
                      button: "Reset") else { return }
        UsageMonitor.shared.resetCycle()
    }

    @objc private func clearHistory() {
        guard confirm(title: "Clear all usage history?",
                      message: "Every recorded day of mobile and Wi-Fi usage will be deleted.",
                      button: "Clear") else { return }
        UsageMonitor.shared.resetAllHistory()
        updateStatusItem()
    }

    // MARK: - Settings actions

    @objc private func toggleLaunchAtLogin() { LoginItem.toggle() }

    @objc private func toggleShowAll() {
        Settings.shared.showAllProcesses.toggle()
        updateStatusItem()
    }

    @objc private func toggleUsageInMenuBar() {
        Settings.shared.showUsageInMenuBar.toggle()
        updateStatusItem()
    }

    @objc private func toggleConfirmKill() { Settings.shared.confirmKill.toggle() }
    @objc private func toggleNotifyNewPorts() { Settings.shared.notifyNewPorts.toggle() }
    @objc private func toggleWarnOnCap() { Settings.shared.warnOnCap.toggle() }
    @objc private func toggleTrackAll() { Settings.shared.trackAllNetworks.toggle() }

    @objc private func setInterval(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? Double else { return }
        Settings.shared.refreshInterval = seconds
        restartTimer()
    }

    @objc private func refreshNow() {
        ProcessInspector.invalidate()
        rescan()
    }

    // MARK: - Dialogs

    private func confirm(title: String, message: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func promptForNumber(title: String, message: String, initial: String,
                                 placeholder: String) -> Double? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = initial
        input.placeholderString = placeholder
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let cleaned = input.stringValue
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }

    // MARK: - Port names

    private var namesURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = support.appendingPathComponent("PortPilot")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("port_names.json")
    }

    private func savePortNames() {
        let dictionary = portNames.reduce(into: [String: String]()) { $0[String($1.key)] = $1.value }
        if let data = try? JSONSerialization.data(withJSONObject: dictionary) {
            try? data.write(to: namesURL, options: .atomic)
        }
    }

    private func loadPortNames() {
        guard let data = try? Data(contentsOf: namesURL),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        portNames = dictionary.reduce(into: [UInt16: String]()) {
            if let port = UInt16($1.key) { $0[port] = $1.value }
        }
    }
}

/// Login-item registration, skipped when running outside an app bundle.
enum LoginItem {
    private static var available: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app"
    }

    static var isEnabled: Bool {
        guard available else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static func toggle() {
        guard available else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Port Pilot: login item toggle failed — \(error.localizedDescription)")
        }
    }
}

/// First installed editor from a small preference list.
enum EditorLauncher {
    struct Editor {
        let name: String
        let url: URL
    }

    private static let candidates: [(String, String)] = [
        ("com.microsoft.VSCode", "VS Code"),
        ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("dev.zed.Zed", "Zed"),
        ("com.sublimetext.4", "Sublime Text"),
        ("com.jetbrains.WebStorm", "WebStorm"),
        ("com.apple.dt.Xcode", "Xcode"),
    ]

    static let preferred: Editor? = {
        for (bundleID, name) in candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return Editor(name: name, url: url)
            }
        }
        return nil
    }()
}
