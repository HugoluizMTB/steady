import SwiftUI
import AppKit

extension NSColor {
    convenience init(hexString: String) {
        var value = hexString
        if value.hasPrefix("#") { value.removeFirst() }
        let int = UInt64(value, radix: 16) ?? 0
        self.init(srgbRed: CGFloat((int >> 16) & 0xFF) / 255,
                  green: CGFloat((int >> 8) & 0xFF) / 255,
                  blue: CGFloat(int & 0xFF) / 255, alpha: 1)
    }
}

enum CodeHighlighter {
    private static let keywords: Set<String> = [
        "const", "let", "var", "function", "func", "return", "if", "else", "for", "while",
        "switch", "case", "break", "continue", "import", "export", "from", "class", "struct",
        "enum", "extends", "new", "async", "await", "try", "catch", "finally", "throw", "typeof",
        "instanceof", "in", "of", "do", "default", "null", "undefined", "true", "false", "this",
        "super", "yield", "static", "public", "private", "guard", "self", "interface", "type",
        "void", "print", "def", "lambda", "then", "with", "as", "where",
    ]

    private static var rules: [(pattern: String, hex: String)] {
        [
            (#"\.[A-Za-z_][A-Za-z0-9_]*"#, "89ddff"),
            (#"\b[0-9][0-9_\.]*\b"#, "f78c6c"),
            (#"\b("# + keywords.joined(separator: "|") + #")\b"#, "c792ea"),
            (#""(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`"#, "c3e88d"),
            (#"//[^\n]*"#, "637777"),
        ]
    }

    static func attributed(_ code: String, fontSize: CGFloat) -> AttributedString {
        var result = AttributedString(code)
        result.font = .system(size: fontSize, design: .monospaced)
        result.foregroundColor = Color(hex: "d6deeb")
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            for match in regex.matches(in: code, range: NSRange(code.startIndex..., in: code)) {
                let start = result.index(result.startIndex, offsetByCharacters: match.range.location)
                let end = result.index(start, offsetByCharacters: match.range.length)
                result[start..<end].foregroundColor = Color(hex: rule.hex)
            }
        }
        return result
    }

    static func apply(to storage: NSTextStorage, fontSize: CGFloat) {
        let code = storage.string
        let full = NSRange(location: 0, length: (code as NSString).length)
        storage.setAttributes([
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor(hexString: "d6deeb"),
        ], range: full)
        for rule in rules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            for match in regex.matches(in: code, range: full) {
                storage.addAttribute(.foregroundColor, value: NSColor(hexString: rule.hex), range: match.range)
            }
        }
    }
}

struct HighlightingEditor: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var width: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.insertionPointColor = NSColor(white: 1, alpha: 0.85)
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.string = text
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        context.coordinator.textView = textView
        if let storage = textView.textStorage { CodeHighlighter.apply(to: storage, fontSize: fontSize) }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        if context.coordinator.fontSize != fontSize {
            context.coordinator.fontSize = fontSize
        }
        if let storage = textView.textStorage { CodeHighlighter.apply(to: storage, fontSize: fontSize) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: HighlightingEditor
        weak var textView: NSTextView?
        var fontSize: CGFloat
        init(_ parent: HighlightingEditor) { self.parent = parent; self.fontSize = parent.fontSize }
        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            if let storage = textView.textStorage {
                let selected = textView.selectedRange()
                CodeHighlighter.apply(to: storage, fontSize: fontSize)
                textView.setSelectedRange(selected)
            }
        }
    }
}

struct CodeSnapGradient: Identifiable {
    let id: Int
    let colors: [Color]
}

let codeSnapGradients: [CodeSnapGradient] = [
    CodeSnapGradient(id: 0, colors: [Color(hex: "4facfe"), Color(hex: "6fb1fc")]),
    CodeSnapGradient(id: 1, colors: [Color(hex: "a18cd1"), Color(hex: "fbc2eb")]),
    CodeSnapGradient(id: 2, colors: [Color(hex: "ff9a9e"), Color(hex: "fad0c4")]),
    CodeSnapGradient(id: 3, colors: [Color(hex: "0ba360"), Color(hex: "3cba92")]),
    CodeSnapGradient(id: 4, colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")]),
]

private struct SnapChrome: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(hex: "ff5f57")).frame(width: 12, height: 12)
            Circle().fill(Color(hex: "febc2e")).frame(width: 12, height: 12)
            Circle().fill(Color(hex: "28c840")).frame(width: 12, height: 12)
            Spacer()
            Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 18).frame(height: 46)
    }
}

struct CodeSnapLauncher: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "curlybraces").font(.system(size: 30)).foregroundStyle(.white.opacity(0.7))
            Text("Code Snap").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Text("Turn a snippet into a shareable image.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            Button {
                openWindow(id: "codesnap")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: 7) { Image(systemName: "macwindow"); Text("Open Code Snap") }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: "102019"))
                    .padding(.horizontal, 18).frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.36, green: 0.82, blue: 0.55)))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CodeSnapWindow: View {
    @State private var code = ""
    @State private var gradient = 0
    @State private var padding: CGFloat = 44
    @State private var fontSize: CGFloat = 14
    @State private var flash = false

    private let codeWidth: CGFloat = 560

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            ScrollView([.vertical]) {
                editableCard
                    .frame(maxWidth: .infinity)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.25))
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(SteadyPalette.canvas)
        .onAppear {
            if code.isEmpty, let clip = NSPasteboard.general.string(forType: .string) { code = clip }
        }
    }

    private var editableCard: some View {
        VStack(spacing: 0) {
            SnapChrome()
            HighlightingEditor(text: $code, fontSize: fontSize, width: codeWidth)
                .frame(width: codeWidth, height: max(120, estimatedHeight))
                .padding(EdgeInsets(top: 6, leading: 24, bottom: 24, trailing: 24))
        }
        .background(Color(hex: "1c2130"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 26, x: 0, y: 16)
        .padding(padding)
        .background(LinearGradient(colors: codeSnapGradients[gradient].colors, startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var estimatedHeight: CGFloat {
        let lines = max(1, code.split(separator: "\n", omittingEmptySubsequences: false).count)
        return CGFloat(lines) * (fontSize * 1.5) + 12
    }

    // Read-only card used only for image export (matches the editable one).
    private var exportCard: some View {
        VStack(spacing: 0) {
            SnapChrome()
            Text(CodeHighlighter.attributed(code.isEmpty ? "// paste your code…" : code, fontSize: fontSize))
                .lineSpacing(5)
                .frame(width: codeWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(EdgeInsets(top: 6, leading: 24, bottom: 24, trailing: 24))
        }
        .background(Color(hex: "1c2130"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 26, x: 0, y: 16)
        .padding(padding)
        .background(LinearGradient(colors: codeSnapGradients[gradient].colors, startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var toolbar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(codeSnapGradients) { option in
                        Button { gradient = option.id } label: {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(LinearGradient(colors: option.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 32, height: 24)
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(gradient == option.id ? Color.white : .white.opacity(0.15), lineWidth: gradient == option.id ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    Text("Padding").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
                    Slider(value: $padding, in: 12...90).frame(width: 88)
                    Text("Font").font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
                    Slider(value: $fontSize, in: 11...20).frame(width: 76)
                }
                Spacer()
                Button { copyImage() } label: {
                    Label(flash ? "Copied ✓" : "Copy image", systemImage: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Color(red: 0.36, green: 0.82, blue: 0.55).opacity(0.8)).interactive(), in: Capsule())
                Button { saveImage() } label: {
                    Label("Save PNG", systemImage: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    @MainActor private func render() -> NSImage? {
        let renderer = ImageRenderer(content: exportCard)
        renderer.scale = 3
        return renderer.nsImage
    }

    private func copyImage() {
        guard let image = render() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        flash = true
        Task { try? await Task.sleep(for: .seconds(1.4)); flash = false }
    }

    private func saveImage() {
        guard let image = render(), let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "codesnap.png"
        panel.allowedContentTypes = [.png]
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { try? png.write(to: url) }
    }
}
