import SwiftUI
import PRMenubar

@main
struct SteadyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var prStore = SteadyStores.shared.pr

    var body: some Scene {
        Window("Steady", id: "main") {
            WorkspaceView()
                .containerBackground(.thickMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 980, height: 640)
        .defaultLaunchBehavior(.presented)

        Window("Code Snap", id: "codesnap") {
            CodeSnapWindow()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 960, height: 620)

        MenuBarExtra {
            IslandContent(prStore: prStore)
                .background(TransparentWindow())
                .environment(\.colorScheme, .dark)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: prStore.errorText != nil ? "exclamationmark.triangle" : "circle.hexagongrid.fill")
                if prStore.errorText == nil && prStore.openCount > 0 {
                    Text(verbatim: "\(prStore.openCount)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
