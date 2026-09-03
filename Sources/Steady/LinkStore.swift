import Foundation
import AppKit

struct SavedLink: Identifiable, Codable, Sendable {
    let id: UUID
    var url: String
    var title: String
    var category: String
    var added: Date
    var reminder: Date?

    var host: String {
        (URLComponents(string: url)?.host ?? url).replacingOccurrences(of: "www.", with: "")
    }

    var isDue: Bool {
        guard let reminder else { return false }
        return reminder <= Date()
    }
}

@MainActor
@Observable
final class LinkStore {
    private(set) var links: [SavedLink] = []
    var categoryFilter: String?

    @ObservationIgnored private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Steady", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("links.json")
        load()
    }

    var categories: [String] {
        Array(Set(links.map(\.category)))
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var visibleLinks: [SavedLink] {
        let scoped = categoryFilter.map { category in links.filter { $0.category == category } } ?? links
        return scoped.sorted { ($0.reminder ?? .distantFuture, $1.added) < ($1.reminder ?? .distantFuture, $0.added) }
    }

    var dueCount: Int { links.filter(\.isDue).count }

    func add(url rawURL: String, category: String, reminder: Date?) {
        var normalized = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if !normalized.contains("://") { normalized = "https://" + normalized }
        let link = SavedLink(
            id: UUID(),
            url: normalized,
            title: URLComponents(string: normalized)?.host ?? normalized,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            added: Date(),
            reminder: reminder
        )
        links.insert(link, at: 0)
        save()
        fetchTitle(for: link.id, url: normalized)
    }

    func remove(_ link: SavedLink) {
        links.removeAll { $0.id == link.id }
        save()
    }

    func clearReminder(_ link: SavedLink) {
        guard let index = links.firstIndex(where: { $0.id == link.id }) else { return }
        links[index].reminder = nil
        save()
    }

    func open(_ link: SavedLink) {
        guard let url = URL(string: link.url) else { return }
        NSWorkspace.shared.open(url)
    }

    func setFilter(_ category: String?) { categoryFilter = category }

    func contains(url raw: String) -> Bool {
        let normalized = raw.contains("://") ? raw : "https://" + raw
        return links.contains { $0.url == normalized }
    }

    static func looksLikeURL(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(" "), value.count < 2000,
              value.rangeOfCharacter(from: .newlines) == nil else { return false }
        if value.hasPrefix("http://") || value.hasPrefix("https://") { return true }
        let host = value.split(separator: "/").first.map(String.init) ?? value
        return host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
    }

    private func fetchTitle(for id: UUID, url: String) {
        guard let target = URL(string: url) else { return }
        Task {
            var request = URLRequest(url: target)
            request.timeoutInterval = 8
            request.setValue("Mozilla/5.0 (Macintosh) Steady", forHTTPHeaderField: "User-Agent")
            guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
            let html = String(decoding: data.prefix(40000), as: UTF8.self)
            guard let title = Self.extractTitle(html), !title.isEmpty,
                  let index = links.firstIndex(where: { $0.id == id }) else { return }
            links[index].title = title
            save()
        }
    }

    private static func extractTitle(_ html: String) -> String? {
        guard let range = html.range(of: "(?is)<title[^>]*>(.*?)</title>", options: .regularExpression) else { return nil }
        let stripped = String(html[range]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(stripped.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&mdash;": "-", "&ndash;": "-"]
        for (entity, value) in map { result = result.replacingOccurrences(of: entity, with: value) }
        return result
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([SavedLink].self, from: data) else { return }
        links = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(links) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
