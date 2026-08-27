import SwiftUI
import AppKit

@MainActor
public final class ColorPickerModel: ObservableObject {
    @Published public private(set) var colorHistory: [String] = []
    let maxHistory = 12

    public init() {}

    public func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let self = self, let color = color else { return }
            let hex = self.colorToHex(color)
            self.colorHistory.removeAll { $0 == hex }
            self.colorHistory.insert(hex, at: 0)
            if self.colorHistory.count > self.maxHistory {
                self.colorHistory = Array(self.colorHistory.prefix(self.maxHistory))
            }
            self.copy(hex)
        }
    }

    public func copy(_ hex: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
    }

    public func clearHistory() {
        colorHistory.removeAll()
    }

    func colorToHex(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    func rgbString(_ hex: String) -> String {
        var h = hex.uppercased()
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let int = UInt64(h, radix: 16) else { return "" }
        return "rgb(\((int >> 16) & 0xFF), \((int >> 8) & 0xFF), \(int & 0xFF))"
    }

    func swatch(_ hex: String) -> Color {
        var h = hex.uppercased()
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let int = UInt64(h, radix: 16) else { return .gray }
        return Color(red: Double((int >> 16) & 0xFF) / 255,
                     green: Double((int >> 8) & 0xFF) / 255,
                     blue: Double(int & 0xFF) / 255)
    }
}

public struct ColorPickerPanel: View {
    @StateObject private var model = ColorPickerModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Button {
                model.pickColor()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "eyedropper.halffull")
                    Text("Pick a color").fontWeight(.semibold)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Capsule().fill(Color(red: 142 / 255, green: 231 / 255, blue: 189 / 255)))
            }
            .buttonStyle(.plain)

            if let current = model.colorHistory.first {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(model.swatch(current))
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(current).font(.system(size: 20, weight: .semibold).monospaced()).foregroundStyle(.white)
                        Text(model.rgbString(current)).font(.system(size: 12).monospaced()).foregroundStyle(.white.opacity(0.5))
                        Button { model.copy(current) } label: {
                            Text("Copy").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).frame(height: 26)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            } else {
                Text("Sample any pixel on screen. It’s copied and saved here.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.colorHistory.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
                        Spacer()
                        Button("Clear") { model.clearHistory() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(model.colorHistory.dropFirst(), id: \.self) { hex in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(model.swatch(hex))
                                .frame(height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
                                .onTapGesture { model.copy(hex) }
                                .help(hex)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 340)
    }
}
