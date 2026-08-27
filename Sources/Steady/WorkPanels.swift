import SwiftUI

struct WorkPanel: View {
    let activeID: String
    @Binding var draft: String
    @Binding var submitResolve: Bool
    let sent: String
    let onSnooze: () -> Void
    let onResolve: () -> Void
    let onSubmitSlack: () -> Void
    let onNotify: (String) -> Void

    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: "0d1013").opacity(0.96)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.16)))
            .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private var content: some View {
        switch activeID {
        case "slack":
            SlackMockPanel(draft: $draft, submitResolve: $submitResolve, sent: sent,
                       onSubmit: onSubmitSlack, onSnooze: onSnooze, onResolve: onResolve)
        case "claude":
            ClaudeSessionsPanel(onSnooze: onSnooze, onResolve: onResolve)
        case "codex":
            CodexSessionsPanel(onSnooze: onSnooze, onResolve: onResolve)
        case "linear":
            LinearPanel(onSnooze: onSnooze, onResolve: onResolve)
        default:
            GenericPanel(id: activeID, onSnooze: onSnooze, onResolve: onResolve)
        }
    }
}

struct PanelActions: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            iconButton("clock", action: onSnooze)
            iconButton("checkmark.circle", action: onResolve)
        }
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "1e2125").opacity(0.72)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.16)))
                .foregroundStyle(Color.white.opacity(0.85))
        }
        .buttonStyle(.plain)
    }
}

struct PanelHeader: View {
    let context: SteadyContext
    let title: String
    let subtitle: String
    let onSnooze: () -> Void
    let onResolve: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            BrandIcon(context: context, size: 62)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 24, weight: .semibold)).tracking(-0.5).foregroundStyle(SteadyPalette.ink)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(Color(hex: "aeb1b7"))
            }
            Spacer()
            PanelActions(onSnooze: onSnooze, onResolve: onResolve)
        }
        .padding(EdgeInsets(top: 26, leading: 36, bottom: 22, trailing: 28))
    }
}

private struct SlackMockPanel: View {
    @Binding var draft: String
    @Binding var submitResolve: Bool
    let sent: String
    let onSubmit: () -> Void
    let onSnooze: () -> Void
    let onResolve: () -> Void

    private var slack: SteadyContext { SteadyData.context("slack")! }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: slack, title: "#product-design",
                        subtitle: "Acme workspace  ·  3 conversations need you",
                        onSnooze: onSnooze, onResolve: onResolve)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    message("Olivia De Lira Araujo", "10:32 AM", "The onboarding flow is ready for review. Can you check the handoff and empty state before we send it to engineering?")
                    message("Jackson Pires", "10:37 AM", "I left two notes on the workspace switcher. Everything else looks ready.")
                    unreadDivider
                    message("Olivia De Lira Araujo", "10:41 AM", "Perfect — can you confirm which direction we should ship?")
                    if !sent.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("You").font(.system(size: 11)).foregroundStyle(SteadyPalette.mint)
                            Text(sent).font(.system(size: 13)).foregroundStyle(Color(hex: "dff8ec"))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(SteadyPalette.mint.opacity(0.14)))
                        .padding(.leading, 66)
                    }
                }
                .padding(.horizontal, 36).padding(.vertical, 16)
            }
            composer
        }
    }

    private func message(_ name: String, _ time: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 44)).foregroundStyle(Color(hex: "3a3d42"))
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(name).font(.system(size: 15, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
                    Text(time).font(.system(size: 13)).foregroundStyle(Color(hex: "85888e"))
                }
                Text(body).font(.system(size: 15)).foregroundStyle(Color(hex: "dcdee1")).lineSpacing(4)
            }
        }
    }

    private var unreadDivider: some View {
        HStack {
            Rectangle().fill(SteadyPalette.lineStrong).frame(height: 1)
            Text("1 new").font(.system(size: 11)).foregroundStyle(SteadyPalette.mint)
                .padding(.horizontal, 13).padding(.vertical, 4)
                .overlay(Capsule().stroke(SteadyPalette.mint.opacity(0.18)))
            Rectangle().fill(SteadyPalette.lineStrong).frame(height: 1)
        }
    }

    private var composer: some View {
        VStack(spacing: 0) {
            TextEditor(text: $draft)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .foregroundStyle(Color(hex: "f0f1f2"))
                .font(.system(size: 15))
                .frame(height: 84)
                .padding(.horizontal, 16).padding(.top, 8)
            HStack {
                Toggle(isOn: $submitResolve) {
                    Text("Submit and resolve").font(.system(size: 13)).foregroundStyle(Color(hex: "c8cace"))
                }
                .toggleStyle(.checkbox)
                .tint(SteadyPalette.mint)
                Spacer()
                Button(action: onSubmit) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18)).foregroundStyle(Color(hex: "102019"))
                        .frame(width: 52, height: 42)
                        .background(RoundedRectangle(cornerRadius: 10).fill(SteadyPalette.mint))
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.42 : 1)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "181b1f")))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.2)))
        .padding(.horizontal, 24).padding(.bottom, 22).padding(.top, 6)
    }
}

private struct ClaudePanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void
    let onNotify: (String) -> Void

    @State private var prompt = "Challenge the recommendation and list the two biggest risks."
    @State private var response = ""

    private var claude: SteadyContext { SteadyData.context("claude")! }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: claude, title: "Research synthesis",
                        subtitle: "Claude  ·  Product strategy session",
                        onSnooze: onSnooze, onResolve: onResolve)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        Circle().fill(SteadyPalette.mint).frame(width: 7, height: 7)
                        Text("Synthesis ready").font(.system(size: 12)).foregroundStyle(Color(hex: "aeb1b6"))
                    }
                    Text("A calmer command center wins by reducing decisions, not just windows.")
                        .font(.system(size: 30, weight: .medium)).tracking(-1).foregroundStyle(SteadyPalette.ink)
                    Text("The strongest direction is a finite sequence of work contexts with consistent actions. The user should always understand why something is here, what continuing means, and what happens after resolve.")
                        .font(.system(size: 14)).foregroundStyle(Color(hex: "aeb1b6")).lineSpacing(6)
                    HStack(spacing: 14) {
                        insight("01", "Prioritize with context", "Explain urgency through work state, not notification volume.")
                        insight("02", "Preserve momentum", "Resolve and advance without returning to an app switcher.")
                    }
                    if !response.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Claude").font(.system(size: 11)).foregroundStyle(SteadyPalette.mint)
                            Text(response).font(.system(size: 13)).foregroundStyle(Color(hex: "dce1de")).lineSpacing(4)
                        }
                        .padding(16)
                        .background(SteadyPalette.mint.opacity(0.055))
                    }
                }
                .padding(.horizontal, 36).padding(.vertical, 22)
            }
            composer
        }
    }

    private func insight(_ index: String, _ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(index).font(.system(size: 10)).foregroundStyle(SteadyPalette.mint)
                .padding(.bottom, 16)
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(SteadyPalette.ink)
            Text(body).font(.system(size: 12)).foregroundStyle(Color(hex: "8e9196")).lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "181b1f").opacity(0.66)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SteadyPalette.line))
    }

    private var composer: some View {
        HStack(spacing: 14) {
            TextEditor(text: $prompt)
                .scrollContentBackground(.hidden).background(Color.clear)
                .foregroundStyle(.white).font(.system(size: 13)).frame(height: 60)
            Button {
                response = "Two risks stand out: the queue can feel like another inbox if prioritization is opaque, and deep integrations may create inconsistent interaction patterns. Make priority explainable and give every context the same resolve, snooze, and return behaviors."
                prompt = ""
                onNotify("Claude continued the synthesis")
            } label: {
                Image(systemName: "paperplane.fill").font(.system(size: 18)).foregroundStyle(Color(hex: "102019"))
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 10).fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "181b1f")))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.2)))
        .padding(.horizontal, 32).padding(.bottom, 26).padding(.top, 6)
    }
}

private struct CodexPanel: View {
    let onSnooze: () -> Void
    let onResolve: () -> Void
    @State private var command = ""
    @State private var history: [String] = []

    private var codex: SteadyContext { SteadyData.context("codex")! }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: codex, title: "Review ready · steady/desktop #184",
                        subtitle: "main  ·  7m ago  ·  3 files changed",
                        onSnooze: onSnooze, onResolve: onResolve)
            terminal
            HStack(spacing: 0) {
                diffCell("3", "Files changed", .white)
                divider
                diffCell("+42", "Additions", SteadyPalette.positive)
                divider
                diffCell("-8", "Deletions", SteadyPalette.negative)
            }
            .frame(height: 70)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(SteadyPalette.line))
            .padding(.horizontal, 26).padding(.top, 14)
            composer
        }
    }

    private var terminal: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("$ codex session attach steady/desktop").foregroundStyle(Color(hex: "c9ccd0"))
                Text("✓ Attached to session steady/desktop").foregroundStyle(SteadyPalette.mint)
                Text("$ npm test -- --watchAll=false").foregroundStyle(Color(hex: "c9ccd0")).padding(.top, 8)
                Text("✓ 30 tests passed (2 files)").foregroundStyle(SteadyPalette.mint)
                ForEach(history, id: \.self) { item in
                    Text("$ \(item)").foregroundStyle(Color(hex: "c9ccd0")).padding(.top, 8)
                    Text("Command completed successfully.").foregroundStyle(SteadyPalette.mint)
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(height: 300)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: "080b0d")))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SteadyPalette.line))
        .padding(.horizontal, 26).padding(.top, 6)
    }

    private func diffCell(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value).font(.system(size: 15, weight: .medium)).foregroundStyle(color)
            Text(label).font(.system(size: 10)).foregroundStyle(Color(hex: "8e9196"))
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View { Rectangle().fill(SteadyPalette.line).frame(width: 1) }

    private var composer: some View {
        HStack(spacing: 12) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(Color(hex: "96999e"))
            TextField("Ask Codex or type a command", text: $command)
                .textFieldStyle(.plain).foregroundStyle(.white).font(.system(size: 13))
            Button {
                let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                history.append(trimmed); command = ""
            } label: {
                Image(systemName: "paperplane.fill").font(.system(size: 16)).foregroundStyle(Color(hex: "102019"))
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 9).fill(SteadyPalette.mint))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 15).padding(.vertical, 7)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(SteadyPalette.mint.opacity(0.56)))
        .padding(.horizontal, 26).padding(.bottom, 22).padding(.top, 14)
    }
}

struct GenericPanel: View {
    let id: String
    let onSnooze: () -> Void
    let onResolve: () -> Void
    @State private var text = ""

    private var context: SteadyContext { SteadyData.context(id)! }
    private var copy: (title: String, body: String) {
        SteadyData.genericCopy[id] ?? (context.headline, context.detail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(context: context, title: copy.title,
                        subtitle: "\(context.name)  ·  Active context",
                        onSnooze: onSnooze, onResolve: onResolve)
            VStack(alignment: .leading, spacing: 13) {
                Text("Continue where you left off")
                    .font(.system(size: 11)).tracking(1).foregroundStyle(SteadyPalette.mint)
                Text(context.headline)
                    .font(.system(size: 34, weight: .semibold)).tracking(-1.4).foregroundStyle(SteadyPalette.ink)
                Text(copy.body)
                    .font(.system(size: 14)).foregroundStyle(Color(hex: "aeb1b6")).lineSpacing(7)
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden).background(Color.clear)
                    .foregroundStyle(.white).font(.system(size: 14))
                    .frame(height: 130).padding(12)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color(hex: "181b1f").opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(SteadyPalette.lineStrong))
                    .padding(.top, 16)
                Button("Continue") { onResolve() }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: "102019"))
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 9).fill(SteadyPalette.mint))
            }
            .padding(.horizontal, 54).padding(.top, 24)
            Spacer()
        }
    }
}
