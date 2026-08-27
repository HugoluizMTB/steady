import SwiftUI
import AppKit

struct RootView: View {
    @State private var active: String?
    @State private var workspace = SteadyData.workspaces[0]
    @State private var completed = 3
    @State private var snoozed: [String] = []
    @State private var toast: String?
    @State private var toastToken = 0
    @State private var commandOpen = false

    @State private var draft = "Let’s ship the centered workspace direction. I’ll tighten the empty state and hand it to engineering today."
    @State private var submitResolve = true
    @State private var sent = ""

    private var activeIndex: Int { SteadyData.contexts.firstIndex { $0.id == active } ?? -1 }

    var body: some View {
        ZStack {
            SteadyPalette.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                TopBar(workspace: $workspace, completed: completed, showCommand: active == nil) {
                    commandOpen = true
                }
                .frame(height: 94)
                stage
            }
            if let toast {
                ToastView(text: toast)
            }
            if commandOpen {
                CommandPalette(onClose: { commandOpen = false }) { id in
                    commandOpen = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { active = id }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background {
            Button("") { commandOpen = true }.keyboardShortcut("k", modifiers: .command).opacity(0)
            Button("") { if active != nil { withAnimation { active = nil } } }
                .keyboardShortcut(.escape, modifiers: []).opacity(0)
        }
    }

    @ViewBuilder private var stage: some View {
        if active == nil {
            ScrollView {
                ContextDeck(active: $active, snoozed: snoozed, compact: false, onSelect: select)
                    .frame(maxWidth: 656)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                    .padding(.bottom, 72)
            }
        } else {
            HStack(alignment: .top, spacing: 30) {
                WorkPanel(
                    activeID: active!,
                    draft: $draft,
                    submitResolve: $submitResolve,
                    sent: sent,
                    onSnooze: snooze,
                    onResolve: resolve,
                    onSubmitSlack: submitSlack,
                    onNotify: flash
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    ContextDeck(active: $active, snoozed: snoozed, compact: true, onSelect: select)
                        .padding(.vertical, 14)
                }
                .frame(width: 430)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 8)
        }
    }

    private func select(_ id: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            active = active == id ? nil : id
        }
    }

    private func flash(_ message: String) {
        toast = message
        toastToken += 1
        let token = toastToken
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            if toastToken == token { withAnimation { toast = nil } }
        }
    }

    private func advance(_ message: String) {
        completed = min(8, completed + 1)
        let next = SteadyData.contexts[(max(0, activeIndex) + 1) % SteadyData.contexts.count].id
        flash(message)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { active = next }
    }

    private func resolve() {
        advance("Resolved — moving to the next context")
    }

    private func snooze() {
        if let current = active { snoozed = Array(Set(snoozed + [current])) }
        flash("Snoozed for 1 hour")
        withAnimation { active = nil }
    }

    private func submitSlack() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sent = trimmed
        draft = ""
        if submitResolve {
            Task {
                try? await Task.sleep(for: .seconds(0.56))
                advance("Reply sent and conversation resolved")
            }
        } else {
            flash("Reply sent")
        }
    }
}

struct TopBar: View {
    @Binding var workspace: String
    let completed: Int
    let showCommand: Bool
    let onCommand: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 34) {
                Text("Steady")
                    .font(.system(size: 23, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(SteadyPalette.ink)
                    .padding(.vertical, 9)
                ProgressBlock(completed: completed)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WorkspaceSwitcher(workspace: $workspace)

            Group {
                if showCommand {
                    Button(action: onCommand) {
                        HStack(spacing: 5) {
                            Image(systemName: "command").font(.system(size: 12))
                            Text("K").font(.system(size: 13))
                        }
                        .foregroundStyle(Color(hex: "a9acb1"))
                        .frame(minWidth: 62, minHeight: 36)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: "191c1f").opacity(0.75)))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SteadyPalette.line))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 5)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
    }
}

private struct ProgressBlock: View {
    let completed: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 13) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.09)).frame(width: 64, height: 5)
                    Capsule().fill(SteadyPalette.mint)
                        .frame(width: 64 * min(1, Double(completed) / 4), height: 5)
                }
                Text("\(completed) of 8").font(.system(size: 14)).foregroundStyle(Color(hex: "d1d3d6"))
                Capsule().fill(Color.white.opacity(0.09)).frame(width: 32, height: 5)
            }
            Text("Only what needs you now").font(.system(size: 14)).foregroundStyle(Color(hex: "b8bbc0"))
        }
        .frame(width: 202, alignment: .leading)
    }
}

private struct WorkspaceSwitcher: View {
    @Binding var workspace: String
    var body: some View {
        Menu {
            ForEach(SteadyData.workspaces, id: \.self) { item in
                Button(item) { workspace = item }
            }
        } label: {
            HStack(spacing: 24) {
                Text(workspace).font(.system(size: 15)).foregroundStyle(SteadyPalette.ink)
                Image(systemName: "chevron.down").font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
            }
            .padding(.leading, 18).padding(.trailing, 16)
            .frame(minWidth: 218, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "191c1f").opacity(0.78)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ContextDeck: View {
    @Binding var active: String?
    let snoozed: [String]
    let compact: Bool
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: compact ? 30 : 44) {
            ForEach(SteadyData.contexts) { context in
                ContextCard(
                    context: context,
                    isActive: active == context.id,
                    subdued: active != nil && active != context.id,
                    compact: compact,
                    snoozed: snoozed.contains(context.id)
                ) {
                    onSelect(context.id)
                }
            }
        }
    }
}

private struct ContextCard: View {
    let context: SteadyContext
    let isActive: Bool
    let subdued: Bool
    let compact: Bool
    let snoozed: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                layer.opacity(0.55).offset(x: 13, y: 13)
                layer.opacity(0.8).offset(x: 7, y: 7)
                surface
            }
            .frame(height: compact ? 112 : 124)
        }
        .buttonStyle(.plain)
        .blur(radius: subdued ? 1.9 : 0)
        .opacity(subdued ? 0.5 : 1)
        .onHover { hovering = $0 }
    }

    private var layer: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(SteadyPalette.layer.opacity(0.72))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.09)))
    }

    private var surface: some View {
        HStack(spacing: 23) {
            BrandIcon(context: context, size: compact ? 56 : 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(context.name)
                    .font(.system(size: compact ? 18 : 20, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Color(hex: "f1f2f4"))
                Text(context.headline)
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: "b2b5ba"))
                    .lineLimit(1)
                statusLine
            }
            Spacer(minLength: 8)
            HStack(spacing: 14) {
                Text("\(context.remaining) left").font(.system(size: 13)).foregroundStyle(Color(hex: "b9bbc0"))
                Image(systemName: "chevron.right").font(.system(size: 15)).foregroundStyle(Color(hex: "aeb0b5"))
            }
        }
        .padding(.leading, 25)
        .padding(.trailing, 32)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 25).fill(SteadyPalette.surface))
        .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.white.opacity(hovering || isActive ? 0.27 : 0.14)))
        .shadow(color: .black.opacity(0.24), radius: 25, x: 0, y: 22)
    }

    @ViewBuilder private var statusLine: some View {
        if snoozed {
            Text("Snoozed for 1 hour").font(.system(size: 13)).foregroundStyle(Color(hex: "8b8e95"))
        } else if let status = context.status {
            HStack(spacing: 7) {
                Circle().fill(Color(hex: "69d39e")).frame(width: 7, height: 7)
                Text(status).font(.system(size: 13)).foregroundStyle(Color(hex: "74cfa2"))
            }
        } else {
            Text(context.detail).font(.system(size: 13)).foregroundStyle(Color(hex: "8b8e95"))
        }
    }
}

private struct ToastView: View {
    let text: String
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color(hex: "d9efe4"))
                .padding(.horizontal, 20).padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color(hex: "191d1f").opacity(0.96)))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(SteadyPalette.mint.opacity(0.22)))
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
                .padding(.bottom, 28)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct CommandPalette: View {
    let onClose: () -> Void
    let onSelect: (String) -> Void
    @State private var query = ""

    private var results: [SteadyContext] {
        guard !query.isEmpty else { return SteadyData.contexts }
        return SteadyData.contexts.filter {
            "\($0.name) \($0.headline)".lowercased().contains(query.lowercased())
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.58).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                HStack(spacing: 13) {
                    Image(systemName: "command").foregroundStyle(Color(hex: "85898f"))
                    TextField("Jump to a context…", text: $query)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .font(.system(size: 15))
                    Text("ESC").font(.system(size: 9)).foregroundStyle(SteadyPalette.muted)
                        .padding(4).overlay(RoundedRectangle(cornerRadius: 5).stroke(SteadyPalette.line))
                }
                .padding(.horizontal, 20).frame(height: 68)
                Rectangle().fill(SteadyPalette.line).frame(height: 1)
                VStack(spacing: 4) {
                    ForEach(results) { context in
                        Button { onSelect(context.id) } label: {
                            HStack(spacing: 13) {
                                BrandIcon(context: context, size: 38)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(context.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                    Text(context.headline).font(.system(size: 11)).foregroundStyle(SteadyPalette.muted).lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(SteadyPalette.muted)
                            }
                            .padding(.horizontal, 12).frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
            .frame(width: 580)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "14171b").opacity(0.98)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SteadyPalette.lineStrong))
            .padding(.top, 140)
        }
    }
}
