import SwiftUI

extension Color {
    init(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        let int = UInt64(value, radix: 16) ?? 0
        self = Color(
            red: Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8) & 0xFF) / 255,
            blue: Double(int & 0xFF) / 255
        )
    }
}

enum SteadyPalette {
    static let canvas = Color(hex: "07090b")
    static let ink = Color(hex: "f4f6f8")
    static let muted = Color(hex: "8f9299")
    static let surface = Color(hex: "15181c")
    static let layer = Color(hex: "16191d")
    static let mint = Color(hex: "8ee7bd")
    static let positive = Color(hex: "70ce99")
    static let negative = Color(hex: "ff646b")
    static let line = Color.white.opacity(0.13)
    static let lineStrong = Color.white.opacity(0.22)
}

struct SteadyContext: Identifiable {
    let id: String
    let name: String
    let headline: String
    let detail: String
    let status: String?
    let remaining: Int
    let symbol: String
    let iconColor: Color
    let iconBackground: Color
}

enum SteadyData {
    static let workspaces = ["Acme — Product", "Globex — Engineering", "Personal — Focus"]

    static let contexts: [SteadyContext] = [
        SteadyContext(id: "claude", name: "Claude", headline: "Continue research synthesis", detail: "2 active sessions", status: "Ready", remaining: 2, symbol: "sparkles", iconColor: .white, iconBackground: Color(hex: "d87656")),
        SteadyContext(id: "slack", name: "Slack", headline: "3 conversations need you", detail: "Product & Design", status: nil, remaining: 5, symbol: "number", iconColor: Color(hex: "e01e5a"), iconBackground: Color(hex: "101214")),
        SteadyContext(id: "codex", name: "Codex", headline: "Review ready · steady/desktop #184", detail: "3 files changed", status: "Tests passed", remaining: 3, symbol: "chevron.left.forwardslash.chevron.right", iconColor: Color(hex: "f4f6f8"), iconBackground: Color(hex: "10a37f")),
        SteadyContext(id: "github", name: "GitHub", headline: "Open pull requests", detail: "Repos · reviews · notifications", status: nil, remaining: 0, symbol: "chevron.left.forwardslash.chevron.right", iconColor: Color(hex: "181717"), iconBackground: Color(hex: "f4f6f8")),
        SteadyContext(id: "linear", name: "Linear", headline: "2 issues assigned", detail: "Sprint 34", status: nil, remaining: 4, symbol: "square.stack.3d.up.fill", iconColor: Color(hex: "7472ff"), iconBackground: Color(hex: "151823")),
        SteadyContext(id: "notion", name: "Notion", headline: "Weekly planning draft", detail: "Edited 18m ago", status: nil, remaining: 3, symbol: "doc.text.fill", iconColor: Color(hex: "111111"), iconBackground: Color(hex: "f4f6f8")),
        SteadyContext(id: "figma", name: "Figma", headline: "Handoff comments ready", detail: "Onboarding v4", status: nil, remaining: 2, symbol: "pentagon.fill", iconColor: Color(hex: "ff7262"), iconBackground: Color(hex: "121418")),
        SteadyContext(id: "gmail", name: "Gmail", headline: "Reply to customer thread", detail: "Pilot onboarding", status: nil, remaining: 4, symbol: "envelope.fill", iconColor: Color(hex: "ea4335"), iconBackground: Color(hex: "f4f6f8")),
        SteadyContext(id: "calendar", name: "Calendar", headline: "Prepare product review", detail: "Today at 2:00 PM", status: nil, remaining: 1, symbol: "calendar", iconColor: Color(hex: "1a73e8"), iconBackground: Color(hex: "f4f6f8")),
    ]

    static let genericCopy: [String: (title: String, body: String)] = [
        "claude": ("Research synthesis", "The competitive notes are organized into three themes. Continue shaping the recommendation or ask Claude to challenge the assumptions."),
        "linear": ("LIN-1842 · Workspace switcher", "Confirm the centered selector behavior, empty-state copy, and keyboard focus order before moving this issue to Ready for engineering."),
        "notion": ("Weekly planning draft", "This week: ship the workspace shell, validate the Slack flow, and test resolve-and-advance with five real work contexts."),
        "figma": ("Onboarding v4 handoff", "Two comments need a decision before the component set is ready for engineering handoff."),
        "gmail": ("Pilot onboarding", "The customer is ready to confirm the pilot scope and needs a concise response with next steps."),
        "calendar": ("Product review preparation", "Collect the open decisions and turn them into a short agenda before the 2:00 PM review."),
        "codex": ("Review ready · steady/desktop #184", "Tests passed on main. Review the diff and continue, or hand it back to Codex with a follow-up."),
    ]

    static func context(_ id: String?) -> SteadyContext? {
        contexts.first { $0.id == id }
    }
}

struct BrandIcon: View {
    let context: SteadyContext
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            Circle().fill(context.iconBackground)
            if let glyph = BrandGlyph.paths[context.id] {
                SVGShape(glyph)
                    .fill(context.iconColor)
                    .frame(width: size * 0.5, height: size * 0.5)
            } else {
                Image(systemName: context.symbol)
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(context.iconColor)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(Color.white.opacity(0.14)))
        .shadow(color: .black.opacity(0.24), radius: 12, x: 0, y: 10)
    }
}
