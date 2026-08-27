import SwiftUI

public struct ClipboardPanel: View {
    @ObservedObject private var manager: ClipboardManager
    @State private var copiedID: UUID?

    public init(manager: ClipboardManager) { self.manager = manager }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clipboard History").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text("\(manager.history.count)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                if !manager.history.isEmpty {
                    Button { manager.clearHistory() } label: {
                        Text("Clear").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).frame(height: 46)
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            if manager.history.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 22)).foregroundStyle(.white.opacity(0.3))
                    Text("No clipboard history yet").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(manager.history) { item in row(item) }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 340, height: 460)
    }

    private func row(_ item: ClipboardItem) -> some View {
        Button {
            manager.copyToClipboard(item: item)
            copiedID = item.id
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.content).font(.system(size: 13)).foregroundStyle(.white).lineLimit(2)
                    Text(item.date, style: .time).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
                Spacer(minLength: 8)
                Image(systemName: copiedID == item.id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(copiedID == item.id ? Color(red: 0.36, green: 0.82, blue: 0.55) : .white.opacity(0.35))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
