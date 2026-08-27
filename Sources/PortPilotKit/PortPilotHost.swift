import AppKit
import Combine

extension AppDelegate {
    func usageDisplay() -> (title: String, detail: String) {
        let usage = UsageMonitor.shared
        guard usage.pathSatisfied else { return ("Offline", "") }
        if usage.isMetered {
            let detail = "\(Fmt.bytes(usage.sessionTotal)) this session  ·  \(Fmt.bytes(usage.cycleUsage.total)) this cycle"
            return ("\(usage.networkLabel)  ·  metered", detail)
        }
        return ("Data Usage", "\(usage.networkLabel) · not metered · \(Fmt.bytes(usage.cycleUsage.total)) mobile this cycle")
    }

    var showingScope: String { Settings.shared.showAllProcesses ? "all processes" : "dev servers" }

    func portDisplays() -> [PortDisplayPublic] {
        PortScanner.shared.visiblePorts(names: portNames).map {
            PortDisplayPublic(id: "\($0.pid):\($0.port)", port: $0.port, name: portNames[$0.port],
                              command: $0.command, loopbackOnly: $0.loopbackOnly, pid: $0.pid)
        }
    }

    func scanNow(_ done: @escaping () -> Void) {
        PortScanner.shared.scan { _ in done() }
    }

    func killPid(_ pid: Int32) { terminate(pids: [pid]) }
}

public struct PortDisplayPublic: Identifiable {
    public let id: String
    public let port: UInt16
    public let name: String?
    public let command: String
    public let loopbackOnly: Bool
    public let pid: Int32
}

@MainActor
public final class PortPilotHost: ObservableObject {
    private let controller = AppDelegate()
    public let menu: NSMenu

    @Published public private(set) var usageTitle = "Data Usage"
    @Published public private(set) var usageDetail = ""
    @Published public private(set) var scope = "dev servers"
    @Published public private(set) var ports: [PortDisplayPublic] = []

    private var timer: Timer?

    public init() {
        menu = controller.attach()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    public func refresh() {
        let usage = controller.usageDisplay()
        usageTitle = usage.title
        usageDetail = usage.detail
        scope = controller.showingScope
        ports = controller.portDisplays()
        controller.scanNow { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.ports = self.controller.portDisplays()
                let refreshed = self.controller.usageDisplay()
                self.usageTitle = refreshed.title
                self.usageDetail = refreshed.detail
            }
        }
    }

    public func kill(_ pid: Int32) {
        controller.killPid(pid)
        refresh()
    }

    public func openBrowser(_ port: UInt16) {
        if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
    }

    public func popFullMenu() {
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}
