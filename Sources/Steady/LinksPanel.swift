import SwiftUI
import AppKit

struct LinksPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void

    private let store = SteadyStores.shared.links
    @State private var url = ""
    @State private var category = ""
    @State private var reminder: Date?
    @State private var showingReminder = false

    private var context: SteadyContext { SteadyData.context("links")! }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: context, title: "Saved", subtitle: subtitle, onSnooze: onSnooze, onResolve: onResolve)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            addBar
            if let clip = clipboardSuggestion { suggestionRow(clip) }
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            if !store.categories.isEmpty { filterChips }
            content
        }
    }

    private var subtitle: String {
        let due = store.dueCount
        return "\(store.links.count) saved\(due > 0 ? "  ·  \(due) due" : "")"
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            field("Paste a link…", text: $url, icon: "link").frame(maxWidth: .infinity)
            field("Category", text: $category, icon: nil).frame(width: 130)
            Button { showingReminder = true } label: {
                Image(systemName: reminder == nil ? "bell" : "bell.fill").font(.system(size: 12))
                    .foregroundStyle(reminder == nil ? SteadyPalette.muted : SteadyPalette.mint)
                    .frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(reminder == nil ? SteadyPalette.line : SteadyPalette.mint.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingReminder, arrowEdge: .bottom) { reminderPicker }

            Button(action: save) {
                Text("Save").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "102019"))
                    .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
            .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func field(_ prompt: String, text: Binding<String>, icon: String?) -> some View {
        HStack(spacing: 7) {
            if let icon { Image(systemName: icon).font(.system(size: 12)).foregroundStyle(SteadyPalette.muted) }
            TextField(prompt, text: text).textFieldStyle(.plain).font(.system(size: 13)).foregroundStyle(SteadyPalette.ink).onSubmit(save)
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SteadyPalette.line))
    }

    private var reminderPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Remind me").font(.system(size: 12, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
            DatePicker("", selection: Binding(get: { reminder ?? Date().addingTimeInterval(3600) }, set: { reminder = $0 }), in: Date()...)
                .datePickerStyle(.graphical).labelsHidden().frame(width: 258)
            HStack {
                Button("Clear") { reminder = nil; showingReminder = false }.buttonStyle(.plain).foregroundStyle(SteadyPalette.muted).font(.system(size: 12))
                Spacer()
                Button("Done") { showingReminder = false }.buttonStyle(.plain).foregroundStyle(SteadyPalette.mint).font(.system(size: 12, weight: .semibold))
            }
        }
        .padding(14).frame(width: 286).background(SteadyPalette.canvas)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", active: store.categoryFilter == nil) { store.setFilter(nil) }
                ForEach(store.categories, id: \.self) { category in
                    chip(category, active: store.categoryFilter == category) {
                        store.setFilter(store.categoryFilter == category ? nil : category)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
        }
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? Color(hex: "102019") : SteadyPalette.muted)
                .padding(.horizontal, 10).frame(height: 26)
                .background(Capsule().fill(active ? SteadyPalette.mint : Color.white.opacity(0.04)))
                .overlay(Capsule().stroke(active ? Color.clear : SteadyPalette.line))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        if store.visibleLinks.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bookmark").font(.system(size: 26)).foregroundStyle(SteadyPalette.muted)
                Text(store.links.isEmpty ? "Nothing saved yet. Paste a link above." : "Nothing in this category.")
                    .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.visibleLinks) { link in
                        LinkRow(link: link, onOpen: { store.open(link) }, onDelete: { store.remove(link) })
                    }
                }
                .padding(16)
            }
        }
    }

    private func save() {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.add(url: trimmed, category: category, reminder: reminder)
        url = ""; category = ""; reminder = nil
    }

    private var clipboardSuggestion: String? {
        guard url.trimmingCharacters(in: .whitespaces).isEmpty,
              let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              LinkStore.looksLikeURL(clip), !store.contains(url: clip) else { return nil }
        return clip
    }

    private func suggestionRow(_ clip: String) -> some View {
        Button { url = clip } label: {
            HStack(spacing: 7) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 11)).foregroundStyle(SteadyPalette.mint)
                Text("Save from clipboard").font(.system(size: 11, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
                Text(hostOf(clip)).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left.circle").font(.system(size: 12)).foregroundStyle(SteadyPalette.mint)
            }
            .padding(.horizontal, 16).frame(height: 32).frame(maxWidth: .infinity)
            .background(SteadyPalette.mint.opacity(0.08))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hostOf(_ raw: String) -> String {
        (URLComponents(string: raw.contains("://") ? raw : "https://" + raw)?.host ?? raw).replacingOccurrences(of: "www.", with: "")
    }
}

private struct LinkRow: View {
    let link: SavedLink
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
                HStack(spacing: 11) {
                    favicon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(link.title).font(.system(size: 13, weight: .medium)).foregroundStyle(SteadyPalette.ink).lineLimit(1)
                        HStack(spacing: 6) {
                            Text(link.host).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                            if !link.category.isEmpty {
                                Text(link.category).font(.system(size: 9, weight: .semibold)).foregroundStyle(SteadyPalette.muted)
                                    .padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Color.white.opacity(0.06)))
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    if let reminder = link.reminder { reminderChip(reminder, due: link.isDue) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hover {
                Button(action: onDelete) {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundStyle(SteadyPalette.muted).frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(hex: "16191d").opacity(0.72)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(link.isDue ? SteadyPalette.mint.opacity(0.35) : SteadyPalette.line))
        .onHover { hover = $0 }
    }

    private var favicon: some View {
        AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?sz=64&domain=\(link.host)")) { image in
            image.resizable().interpolation(.high)
        } placeholder: {
            Image(systemName: "globe").font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func reminderChip(_ date: Date, due: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "bell.fill").font(.system(size: 8))
            Text(due ? "due" : shortDate(date)).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(due ? Color(hex: "102019") : SteadyPalette.muted)
        .padding(.horizontal, 7).frame(height: 22)
        .background(Capsule().fill(due ? SteadyPalette.mint : Color.white.opacity(0.05)))
        .overlay(Capsule().stroke(due ? Color.clear : SteadyPalette.line))
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

struct SavedIslandPanel: View {
    private let store = SteadyStores.shared.links
    @State private var url = ""
    @State private var category = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Save a link…", text: $url).textFieldStyle(.plain).font(.system(size: 12)).onSubmit(save)
                }
                .padding(.horizontal, 9).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
                TextField("Tag", text: $category).textFieldStyle(.plain).font(.system(size: 12)).frame(width: 62)
                    .padding(.horizontal, 8).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.05)))
                    .onSubmit(save)
                Button(action: save) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(hex: "102019"))
                        .frame(width: 32, height: 30).background(RoundedRectangle(cornerRadius: 8).fill(SteadyPalette.mint))
                }
                .buttonStyle(.plain).disabled(url.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let clip = clipboardSuggestion {
                Button { url = clip } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 10)).foregroundStyle(SteadyPalette.mint)
                        Text("Clipboard:").font(.system(size: 11, weight: .semibold))
                        Text(hostOf(clip)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9).frame(height: 26).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 7).fill(SteadyPalette.mint.opacity(0.12)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if store.links.isEmpty {
                Text("Nothing saved yet.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 10)
            } else {
                VStack(spacing: 5) {
                    ForEach(store.visibleLinks.prefix(6)) { link in
                        Button { store.open(link) } label: {
                            HStack(spacing: 8) {
                                AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?sz=32&domain=\(link.host)")) { image in
                                    image.resizable()
                                } placeholder: {
                                    Image(systemName: "globe").font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                .frame(width: 15, height: 15).clipShape(RoundedRectangle(cornerRadius: 3))
                                Text(link.title).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 6)
                                if link.isDue { Circle().fill(SteadyPalette.mint).frame(width: 6, height: 6) }
                                Text(link.category.isEmpty ? link.host : link.category).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(.horizontal, 8).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(2)
    }

    private var clipboardSuggestion: String? {
        guard url.trimmingCharacters(in: .whitespaces).isEmpty,
              let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              LinkStore.looksLikeURL(clip), !store.contains(url: clip) else { return nil }
        return clip
    }

    private func hostOf(_ raw: String) -> String {
        (URLComponents(string: raw.contains("://") ? raw : "https://" + raw)?.host ?? raw).replacingOccurrences(of: "www.", with: "")
    }

    private func save() {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.add(url: trimmed, category: category, reminder: nil)
        url = ""; category = ""
    }
}
