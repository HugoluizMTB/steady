import Foundation
import AppKit

@MainActor
@Observable
final class MailStore {
    enum Access { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var accounts: [String] = []
    private(set) var messages: [MailMessage] = []
    private(set) var loading = false
    private(set) var sending = false

    private(set) var openMessage: MailMessage?
    private(set) var openBody = ""
    private(set) var loadingBody = false

    var mutedSenders: Set<String> {
        didSet { UserDefaults.standard.set(Array(mutedSenders), forKey: Self.mutedKey) }
    }

    private static let mutedKey = "mail.mutedSenders"

    init() {
        mutedSenders = Set(UserDefaults.standard.stringArray(forKey: Self.mutedKey) ?? [])
        if MailAutomation.everGranted {
            access = .granted
            connect()
        }
    }

    var visibleMessages: [MailMessage] {
        messages.filter { !mutedSenders.contains($0.senderEmail) }
    }

    var unreadCount: Int {
        visibleMessages.filter { $0.unread }.count
    }

    var senders: [SenderSummary] {
        var order: [String] = []
        var info: [String: (name: String, count: Int)] = [:]
        for message in messages {
            if info[message.senderEmail] == nil { order.append(message.senderEmail) }
            let previous = info[message.senderEmail]
            info[message.senderEmail] = (message.senderName, (previous?.count ?? 0) + 1)
        }
        return order.map { SenderSummary(email: $0, name: info[$0]?.name ?? $0, count: info[$0]?.count ?? 0) }
    }

    func connect() {
        loading = true
        Task {
            let result = await Task.detached { MailBridge.accounts() }.value
            MailAutomation.recordResult(result)
            if result.authDenied {
                access = .denied
                loading = false
                return
            }
            access = .granted
            accounts = MailBridge.parseAccounts(result.output)
            load()
        }
    }

    func refresh() {
        if access == .granted { load() }
    }

    func load() {
        loading = true
        Task {
            let result = await Task.detached { MailBridge.recent(limit: 60) }.value
            MailAutomation.recordResult(result)
            if result.authDenied {
                access = .denied
                loading = false
                return
            }
            messages = MailBridge.parseMessages(result.output)
            loading = false
        }
    }

    func open(_ message: MailMessage) {
        openMessage = message
        openBody = ""
        loadingBody = true
        Task {
            let result = await Task.detached { MailBridge.body(id: message.id) }.value
            openBody = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            loadingBody = false
            markRead(message)
        }
    }

    func closeOpen() {
        openMessage = nil
        openBody = ""
    }

    func toggleMute(_ email: String) {
        if mutedSenders.contains(email) { mutedSenders.remove(email) } else { mutedSenders.insert(email) }
    }

    func showAll() {
        mutedSenders.removeAll()
    }

    func send(to: String, subject: String, body: String, completion: @escaping (Bool) -> Void) {
        sending = true
        Task {
            let result = await Task.detached { MailBridge.send(to: to, subject: subject, body: body) }.value
            sending = false
            completion(result.ok && !result.authDenied)
        }
    }

    private func markRead(_ message: MailMessage) {
        guard message.unread, let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        let current = messages[index]
        messages[index] = MailMessage(id: current.id, senderName: current.senderName, senderEmail: current.senderEmail, subject: current.subject, dateText: current.dateText, unread: false)
        Task { _ = await Task.detached { MailBridge.markRead(id: message.id) }.value }
    }
}

struct SenderSummary: Identifiable {
    let email: String
    let name: String
    let count: Int
    var id: String { email }
}
