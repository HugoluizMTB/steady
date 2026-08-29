import Foundation

@MainActor
@Observable
final class SettingsStore {
    var hiddenTools: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenTools), forKey: Self.hiddenKey) }
    }
    var autoRefreshMinutes: Int {
        didSet { UserDefaults.standard.set(autoRefreshMinutes, forKey: Self.refreshKey) }
    }

    private static let hiddenKey = "steady.hiddenTools"
    private static let refreshKey = "steady.autoRefreshMinutes"

    init() {
        hiddenTools = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? [])
        autoRefreshMinutes = UserDefaults.standard.object(forKey: Self.refreshKey) as? Int ?? 0
    }

    func isHidden(_ id: String) -> Bool { hiddenTools.contains(id) }

    func toggleHidden(_ id: String) {
        if hiddenTools.contains(id) { hiddenTools.remove(id) } else { hiddenTools.insert(id) }
    }
}
