import PRMenubar
import PortPilotKit
import ClipboardKit

@MainActor
final class SteadyStores {
    static let shared = SteadyStores()
    let pr = PRStore()
    let portPilot = PortPilotHost()
    let sessions = SessionStore()
    let linear = LinearProvider()
    let slack = SlackProvider()
    let clipboard = ClipboardManager()
    private init() {}
}
