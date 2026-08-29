import Foundation

@MainActor
@Observable
final class TriageCenter {
    private(set) var snoozedUntil: [String: Date] = [:]

    private static let key = "steady.snoozed"

    init() {
        if let raw = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Double] {
            snoozedUntil = raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    func isSnoozed(_ id: String) -> Bool {
        guard let until = snoozedUntil[id] else { return false }
        if until <= Date() {
            snoozedUntil[id] = nil
            persist()
            return false
        }
        return true
    }

    func snooze(_ id: String, minutes: Int = 60) {
        snoozedUntil[id] = Date().addingTimeInterval(Double(minutes) * 60)
        persist()
    }

    func clear(_ id: String) {
        snoozedUntil[id] = nil
        persist()
    }

    func clearAll() {
        snoozedUntil.removeAll()
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(snoozedUntil.mapValues { $0.timeIntervalSince1970 }, forKey: Self.key)
    }
}
