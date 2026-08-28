import SwiftUI

struct ComingSoonPanel: View {
    let id: String
    let onSnooze: () -> Void
    let onResolve: () -> Void

    private var context: SteadyContext { SteadyData.context(id) ?? SteadyData.contexts[0] }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(context: context, title: context.name, subtitle: "Coming soon", onSnooze: onSnooze, onResolve: onResolve)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            VStack(spacing: 12) {
                BrandIcon(context: context, size: 54).saturation(0.5).opacity(0.7)
                Text("SOON").font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(Color(hex: "102019"))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(SteadyPalette.mint.opacity(0.85)))
                Text("The \(context.name) tool isn't ready yet.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(SteadyPalette.ink)
                Text("It'll show up right here when it lands.")
                    .font(.system(size: 12)).foregroundStyle(SteadyPalette.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
