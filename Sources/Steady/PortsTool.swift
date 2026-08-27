import SwiftUI
import AppKit
import PortPilotKit

struct PortsPanel: View {
    @ObservedObject private var host = SteadyStores.shared.portPilot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            dataUsageRow
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
            portsHeader
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(host.ports) { port in portRow(port) }
                }
            }
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 340)
        .onAppear { host.refresh() }
    }

    private var dataUsageRow: some View {
        Button { host.popFullMenu() } label: {
            HStack(spacing: 11) {
                Image(systemName: "wifi")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(red: 0.42, green: 0.53, blue: 1.0))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.usageTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Text(host.usageDetail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 14).frame(height: 54).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var portsHeader: some View {
        Text(verbatim: host.ports.isEmpty
             ? "No active ports  ·  \(host.scope)"
             : "\(host.ports.count) active port\(host.ports.count == 1 ? "" : "s")  ·  \(host.scope)")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.45))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
    }

    private func portRow(_ port: PortDisplayPublic) -> some View {
        HStack(spacing: 11) {
            Circle().fill(port.loopbackOnly ? Color(red: 0.36, green: 0.82, blue: 0.55) : Color.orange)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ":\(port.port)  \(port.name ?? port.command)")
                    .font(.system(size: 13)).foregroundStyle(.white)
                if port.name != nil {
                    Text(port.command).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
            }
            Spacer(minLength: 6)
            Button { host.openBrowser(port.port) } label: {
                Image(systemName: "safari").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            Button { host.kill(port.pid) } label: {
                Image(systemName: "xmark.octagon.fill").font(.system(size: 13)).foregroundStyle(Color(red: 1, green: 0.39, blue: 0.42))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).frame(height: port.name != nil ? 46 : 38)
    }

    private var footer: some View {
        HStack {
            Button { host.popFullMenu() } label: {
                HStack(spacing: 6) { Image(systemName: "gearshape"); Text("Settings & history") }
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
            Spacer()
            Button { host.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}
