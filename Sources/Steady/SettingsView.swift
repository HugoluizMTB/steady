import SwiftUI

struct SettingsView: View {
    let onClose: () -> Void

    private let settings = SteadyStores.shared.settings
    private let triage = SteadyStores.shared.triage
    @AppStorage("steady.onboardingDone") private var onboardingDone = false

    private let intervals = [0, 5, 15, 30]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 14, weight: .semibold)).foregroundStyle(SteadyPalette.ink)
                Spacer()
                Button("Done", action: onClose).buttonStyle(.plain).foregroundStyle(SteadyPalette.mint).font(.system(size: 13, weight: .semibold))
            }
            .padding(16)
            Rectangle().fill(SteadyPalette.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    toolsSection
                    refreshSection
                    resetSection
                }
                .padding(18)
            }
        }
        .frame(width: 420, height: 540)
        .background(SteadyPalette.canvas)
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Tools in the top bar")
            ForEach(PaneApp.allCases) { tool in
                Toggle(isOn: Binding(
                    get: { !settings.isHidden(tool.id) },
                    set: { _ in settings.toggleHidden(tool.id) }
                )) {
                    HStack(spacing: 9) {
                        BrandIcon(context: tool.context, size: 22)
                        Text(tool.context.name).font(.system(size: 13)).foregroundStyle(SteadyPalette.ink)
                    }
                }
                .toggleStyle(.switch)
                .tint(SteadyPalette.mint)
            }
        }
    }

    private var refreshSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Auto-refresh")
            Picker("", selection: Binding(get: { settings.autoRefreshMinutes }, set: { settings.autoRefreshMinutes = $0 })) {
                ForEach(intervals, id: \.self) { minutes in
                    Text(minutes == 0 ? "Off" : "\(minutes) min").tag(minutes)
                }
            }
            .pickerStyle(.segmented).labelsHidden()
            Text("Refreshes GitHub, Mail, Calendar, Notion and Linear on this interval.")
                .font(.system(size: 11)).foregroundStyle(SteadyPalette.muted)
        }
    }

    private var resetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Reset")
            HStack(spacing: 10) {
                resetButton("Clear snoozes") { triage.clearAll() }
                resetButton("Replay onboarding") { onboardingDone = false; onClose() }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(SteadyPalette.muted)
    }

    private func resetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(SteadyPalette.ink)
                .padding(.horizontal, 12).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(SteadyPalette.line))
        }
        .buttonStyle(.plain)
    }
}
