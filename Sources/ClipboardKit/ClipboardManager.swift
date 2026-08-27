import SwiftUI
import Combine

public struct ClipboardItem: Identifiable, Equatable {
    public let id = UUID()
    public let content: String
    public let date: Date
}

public class ClipboardManager: ObservableObject {
    @Published public var history: [ClipboardItem] = []
    private var lastChangeCount: Int
    private var timer: AnyCancellable?

    public init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
        startMonitoring()
    }

    private func startMonitoring() {
        timer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkClipboard()
                self?.cleanupOldItems()
            }
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        if pasteboard.changeCount != lastChangeCount {
            lastChangeCount = pasteboard.changeCount

            if let content = pasteboard.string(forType: .string) {
                if history.first?.content != content {
                    let newItem = ClipboardItem(content: content, date: Date())
                    history.insert(newItem, at: 0)
                }
            }
        }
    }

    private func cleanupOldItems() {
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        if let lastItem = history.last, lastItem.date < twentyFourHoursAgo {
            history.removeAll { $0.date < twentyFourHoursAgo }
        }
    }

    public func copyToClipboard(item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.content, forType: .string)
    }

    public func clearHistory() {
        history.removeAll()
    }
}
