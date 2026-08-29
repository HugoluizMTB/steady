import SwiftUI

struct CommandPalette: View {
    let tools: [PaneApp]
    let onClose: () -> Void
    let onSelect: (PaneApp) -> Void

    @State private var query = ""

    private var results: [PaneApp] {
        guard !query.isEmpty else { return tools }
        return tools.filter { $0.context.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "command").foregroundStyle(SteadyPalette.muted)
                    TextField("Jump to a tool…", text: $query)
                        .textFieldStyle(.plain).foregroundStyle(.white).font(.system(size: 15))
                    Text("ESC").font(.system(size: 9)).foregroundStyle(SteadyPalette.muted)
                        .padding(4).overlay(RoundedRectangle(cornerRadius: 5).stroke(SteadyPalette.line))
                }
                .padding(.horizontal, 18).frame(height: 60)
                Rectangle().fill(SteadyPalette.line).frame(height: 1)
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(results) { tool in
                            Button { onSelect(tool) } label: {
                                HStack(spacing: 12) {
                                    BrandIcon(context: tool.context, size: 30)
                                    Text(tool.context.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                    if tool.comingSoon {
                                        Text("soon").font(.system(size: 9, weight: .bold)).foregroundStyle(SteadyPalette.muted)
                                    }
                                    Spacer()
                                    Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
                                }
                                .padding(.horizontal, 12).frame(height: 46).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 320)
            }
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "14171b").opacity(0.98)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SteadyPalette.lineStrong))
            .padding(.top, 120)
        }
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12)).foregroundStyle(Color(hex: "d9efe4"))
                .padding(.horizontal, 18).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 11).fill(Color(hex: "191d1f").opacity(0.96)))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(SteadyPalette.mint.opacity(0.22)))
                .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 10)
                .padding(.bottom, 24)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}
