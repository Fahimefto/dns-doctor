import SwiftUI
import ServiceManagement

struct StatusView: View {
    @ObservedObject var monitor: DNSMonitor
    @AppStorage(DNSMonitor.notifyKey) private var notifyOnBreak = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var moreFixesExpanded = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            checks
            servers
            actions
            moreFixes
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(statusColor)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.health.title).font(.headline)
                Text(statusSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var checks: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Checks")
            if monitor.dnsResults.isEmpty {
                Text("Running first check…").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(monitor.dnsResults) { row($0) }
            if let net = monitor.internetResult { row(net) }
        }
    }

    private var servers: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("DNS servers in use")
            if monitor.serverResults.isEmpty {
                Text(monitor.lastChecked == nil ? "Looking up…" : "None configured")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(monitor.serverResults) { row($0, monospaced: true) }
            ForEach(monitor.manualDNS, id: \.service) { entry in
                Label {
                    Text("\(entry.service): DNS set manually (\(entry.servers.joined(separator: ", ")))")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button {
                    Task { await monitor.repair() }
                } label: {
                    HStack(spacing: 6) {
                        if monitor.isRepairing { ProgressView().controlSize(.small) }
                        Text(monitor.isRepairing ? "Repairing…" : "Repair DNS")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(monitor.health == .dnsBroken ? .red : .accentColor)
                .controlSize(.large)
                .disabled(monitor.isRepairing)

                Button {
                    Task { await monitor.check() }
                } label: {
                    if monitor.isChecking && !monitor.isRepairing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .controlSize(.large)
                .help("Check now")
                .disabled(monitor.isChecking || monitor.isRepairing)
            }

            if let progress = monitor.repairProgress {
                Text(progress)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let msg = monitor.repairMessage {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var moreFixes: some View {
        DisclosureGroup("More fixes", isExpanded: $moreFixesExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if monitor.usingPublicDNS {
                    Text("Public DNS is on (Cloudflare + Google). Your previous settings are saved and can be put back.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Restore automatic DNS") {
                        Task { await monitor.restoreAutomaticDNS() }
                    }
                } else {
                    Button("Use public DNS (Cloudflare + Google)") {
                        Task { await monitor.usePublicDNS() }
                    }
                    .help("Points every network service at 1.1.1.1 and 8.8.8.8. Reversible.")
                }
                Button(copied ? "Copied" : "Copy diagnostics") { copyDiagnostics() }
                    .help("Copies a plain-text report you can paste into a chat or ticket.")
            }
            .controlSize(.small)
            .disabled(monitor.isRepairing)
            .padding(.top, 6)
        }
        .font(.callout)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Open at login", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
            Toggle("Notify when DNS breaks", isOn: $notifyOnBreak)
                .toggleStyle(.checkbox)
            HStack {
                Text("DNS Doctor \(DNSMonitor.appVersion) · \(lastCheckedText)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
    }

    // MARK: Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func row(_ r: ProbeResult, monospaced: Bool = false) -> some View {
        HStack {
            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(r.ok ? .green : .red)
            Text(r.name)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(r.detail).foregroundStyle(.secondary).monospacedDigit()
        }
        .font(.callout)
    }

    private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(monitor.diagnosticsText(), forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item. Move the app to Applications first."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private var lastCheckedText: String {
        guard let d = monitor.lastChecked else { return "not checked yet" }
        let f = DateFormatter()
        f.timeStyle = .short
        return "checked \(f.string(from: d))"
    }

    private var statusSymbol: String {
        switch monitor.health {
        case .checking: return "hourglass"
        case .healthy: return "checkmark.shield.fill"
        case .dnsBroken: return "exclamationmark.triangle.fill"
        case .offline: return "wifi.slash"
        }
    }

    private var statusColor: Color {
        switch monitor.health {
        case .checking: return .secondary
        case .healthy: return .green
        case .dnsBroken: return .red
        case .offline: return .orange
        }
    }

    private var statusSubtitle: String {
        switch monitor.health {
        case .checking: return "Hang on a second."
        case .healthy: return "Websites are resolving normally. Checks run every 30 seconds."
        case .dnsBroken: return monitor.diagnosis ?? "The internet is reachable, but names can't be looked up. Click Repair DNS."
        case .offline: return "Neither DNS nor the internet is reachable. Check Wi-Fi or the VPN."
        }
    }
}
