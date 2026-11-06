import Foundation
import Network
import UserNotifications

enum DNSHealth: Equatable {
    case checking
    case healthy
    case dnsBroken
    case offline

    var title: String {
        switch self {
        case .checking: return "Checking DNS…"
        case .healthy: return "DNS is working"
        case .dnsBroken: return "DNS is broken"
        case .offline: return "No internet connection"
        }
    }

    /// Exit code for `--check`.
    var exitCode: Int32 {
        switch self {
        case .healthy, .checking: return 0
        case .dnsBroken: return 1
        case .offline: return 2
        }
    }
}

struct ProbeResult: Identifiable {
    let id = UUID()
    let name: String
    let ok: Bool
    let detail: String
}

@MainActor
final class DNSMonitor: ObservableObject {
    @Published private(set) var health: DNSHealth = .checking
    @Published private(set) var diagnosis: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var nameservers: [String] = []
    @Published private(set) var serverResults: [ProbeResult] = []
    @Published private(set) var manualDNS: [NetworkServices.ServiceDNS] = []
    @Published private(set) var usingPublicDNS = DNSRepair.isUsingPublicDNS
    @Published private(set) var dnsResults: [ProbeResult] = []
    @Published private(set) var internetResult: ProbeResult?
    @Published private(set) var isChecking = false
    @Published private(set) var isRepairing = false
    @Published private(set) var repairProgress: String?
    @Published private(set) var repairMessage: String?
    @Published private(set) var lastRepair: Date?

    var onHealthChange: ((DNSHealth) -> Void)?

    static let notifyKey = "notifyOnBreak"

    private let hosts = ["apple.com", "google.com", "cloudflare.com"]
    private let ips: [(String, UInt16)] = [("1.1.1.1", 443), ("8.8.8.8", 443), ("9.9.9.9", 443)]
    private let interval: TimeInterval = 30
    private var timer: Timer?
    private let pathMonitor = NWPathMonitor()
    private var pathSatisfied = true
    private var pendingPathCheck: Task<Void, Never>?
    private var started = false

    // MARK: Lifecycle

    /// Starts background monitoring (menu bar mode). Not used by `--check`.
    func start() {
        started = true
        UserDefaults.standard.register(defaults: [Self.notifyKey: true])
        requestNotificationPermission()

        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.pathSatisfied = path.status == .satisfied
                // Network changed (VPN connect/disconnect, Wi-Fi switch): re-check shortly after.
                self.pendingPathCheck?.cancel()
                self.pendingPathCheck = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if !Task.isCancelled { await self.check() }
                }
            }
        }
        pathMonitor.start(queue: .global(qos: .utility))

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check() }
        }
        Task { await check() }
    }

    // MARK: Checking

    /// Normal check: skipped while another check or a repair is running.
    func check() async {
        guard !isChecking, !isRepairing else { return }
        await performCheck()
    }

    /// One-shot check for `--check`: no confirmation delay, no notifications.
    func checkOnce() async -> DNSHealth {
        await performCheck(confirm: false)
        return health
    }

    /// Unguarded check, also used by repair while `isRepairing` is true.
    private func performCheck(confirm: Bool = true) async {
        isChecking = true
        defer { isChecking = false }

        var newHealth = await runProbes()
        // A single failed round can be a blip; confirm before turning the icon red.
        if confirm && newHealth != .healthy && health == .healthy {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            newHealth = await runProbes()
        }
        setHealth(newHealth)
    }

    private func waitForCheckToFinish() async {
        while isChecking {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func runProbes() async -> DNSHealth {
        let (servers, manual) = await Probes.background {
            (Probes.currentNameservers(), NetworkServices.manualDNS())
        }
        nameservers = servers
        manualDNS = manual
        usingPublicDNS = DNSRepair.isUsingPublicDNS

        async let dns = withTaskGroup(of: ProbeResult.self) { group -> [ProbeResult] in
            for host in hosts {
                group.addTask {
                    if let t = await Probes.resolve(host) {
                        return ProbeResult(name: host, ok: true, detail: "\(Int(t * 1000)) ms")
                    }
                    return ProbeResult(name: host, ok: false, detail: "Can't resolve")
                }
            }
            var all: [ProbeResult] = []
            for await r in group { all.append(r) }
            return all
        }
        async let net = withTaskGroup(of: Bool.self) { group -> Bool in
            for (ip, port) in ips {
                group.addTask { await Probes.reachable(ip, port: port) }
            }
            var any = false
            for await ok in group where ok { any = true }
            return any
        }
        async let direct = withTaskGroup(of: (Int, ProbeResult).self) { group -> [ProbeResult] in
            for (index, server) in servers.enumerated() {
                group.addTask {
                    let ok = await Probes.background { Probes.queryServer(server) }
                    return (index, ProbeResult(name: server, ok: ok,
                                               detail: ok ? "Answering" : "Not answering"))
                }
            }
            var all: [(Int, ProbeResult)] = []
            for await r in group { all.append(r) }
            return all.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        let (dnsList, internetUp, serverList) = await (dns, net, direct)
        let order = Dictionary(uniqueKeysWithValues: hosts.enumerated().map { ($1, $0) })
        dnsResults = dnsList.sorted { order[$0.name, default: 0] < order[$1.name, default: 0] }
        serverResults = serverList
        internetResult = ProbeResult(name: "Internet (by IP, no DNS)",
                                     ok: internetUp,
                                     detail: internetUp ? "Reachable" : "Unreachable")
        lastChecked = Date()

        let dnsUp = dnsList.contains { $0.ok }
        if dnsUp {
            diagnosis = nil
            return .healthy
        }
        if !pathSatisfied || !internetUp {
            diagnosis = nil
            return .offline
        }
        if serverList.contains(where: { $0.ok }) {
            diagnosis = "macOS's DNS service is stuck. Repair will fix it."
        } else if serverList.isEmpty {
            diagnosis = "No DNS servers are configured (often left behind by the VPN)."
        } else {
            diagnosis = "Your DNS servers aren't answering (often left behind by the VPN)."
        }
        return .dnsBroken
    }

    private func setHealth(_ h: DNSHealth) {
        guard h != health else { return }
        let previous = health
        health = h
        onHealthChange?(h)
        if started && h == .dnsBroken && previous != .dnsBroken {
            notifyBroken()
        }
    }

    // MARK: Repair

    func repair() async {
        guard !isRepairing else { return }
        isRepairing = true
        repairMessage = nil
        repairProgress = "Flushing the DNS cache…"
        defer {
            isRepairing = false
            repairProgress = nil
        }
        await waitForCheckToFinish()

        // Level 1: flush cache + reload mDNSResponder (the cdnfix commands).
        switch await DNSRepair.quickFix() {
        case .cancelled:
            repairMessage = "Repair cancelled."
            return
        case .failure(let message):
            repairMessage = "Repair failed: \(message)"
            return
        case .success:
            break
        }
        lastRepair = Date()
        repairProgress = "Cache flushed. Re-checking…"
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await performCheck(confirm: false)

        switch health {
        case .healthy:
            repairMessage = "Fixed. Flushing the DNS cache was enough."
            return
        case .offline:
            repairMessage = "Cache flushed, but the internet itself is unreachable now. Check Wi-Fi or the VPN, then check again."
            return
        default:
            break
        }

        // Level 2: restart mDNSResponder, drop dead manual DNS servers, renew DHCP.
        repairProgress = "Still broken, trying a deeper fix…"
        let plan = await DNSRepair.planDeepFix()
        switch await DNSRepair.deepFix(plan) {
        case .cancelled:
            repairMessage = "Cache flushed, but DNS is still broken. The deeper fix was cancelled."
            return
        case .failure(let message):
            repairMessage = "Deeper fix failed: \(message)"
            return
        case .success:
            break
        }
        lastRepair = Date()

        // Renewing DHCP drops the network for a moment; give it time to come back.
        let deadline = Date().addingTimeInterval(15)
        var attempt = 0
        repeat {
            attempt += 1
            repairProgress = "Waiting for the network to settle… (\(attempt))"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await performCheck(confirm: false)
        } while health != .healthy && Date() < deadline

        if health == .healthy {
            repairMessage = "Fixed by the deeper repair: \(describe(plan))."
        } else {
            repairMessage = "Still broken after both fixes. Try \"Use public DNS\" under More fixes, or disconnect and reconnect the VPN."
        }
    }

    private func describe(_ plan: DNSRepair.DeepPlan) -> String {
        var parts = ["restarted macOS's DNS service"]
        if !plan.resetServices.isEmpty {
            parts.append("reset manual DNS on \(plan.resetServices.joined(separator: ", ")) to automatic")
        }
        if !plan.renewInterfaces.isEmpty {
            parts.append("renewed DHCP on \(plan.renewInterfaces.joined(separator: ", "))")
        }
        return parts.joined(separator: ", ")
    }

    /// Points every network service at Cloudflare + Google DNS (restorable).
    func usePublicDNS() async {
        await runPrivilegedAction(progress: "Switching to public DNS…") {
            await DNSRepair.usePublicDNS()
        } onSuccess: { healthy in
            healthy
                ? "Now using Cloudflare and Google DNS. DNS is working. Your previous settings are saved."
                : "Switched to public DNS, but lookups still fail. Try disconnecting and reconnecting the VPN."
        }
    }

    /// Puts back the DNS settings each service had before "Use public DNS".
    func restoreAutomaticDNS() async {
        await runPrivilegedAction(progress: "Restoring previous DNS settings…") {
            await DNSRepair.restoreDNS()
        } onSuccess: { healthy in
            healthy
                ? "Previous DNS settings restored. DNS is working."
                : "Previous DNS settings restored, but DNS is broken again. Click Repair DNS."
        }
    }

    private func runPrivilegedAction(progress: String,
                                     _ action: () async -> RepairResult,
                                     onSuccess message: (Bool) -> String) async {
        guard !isRepairing else { return }
        isRepairing = true
        repairMessage = nil
        repairProgress = progress
        defer {
            isRepairing = false
            repairProgress = nil
        }
        await waitForCheckToFinish()

        switch await action() {
        case .cancelled:
            repairMessage = "Cancelled. Nothing was changed."
        case .failure(let m):
            repairMessage = "Failed: \(m)"
        case .success:
            lastRepair = Date()
            repairProgress = "Re-checking…"
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await performCheck(confirm: false)
            repairMessage = message(health == .healthy)
        }
        usingPublicDNS = DNSRepair.isUsingPublicDNS
    }

    // MARK: Notifications

    /// UNUserNotificationCenter only works inside an .app bundle; `swift run` has none.
    private var canNotify: Bool { Bundle.main.bundleIdentifier != nil }

    private func requestNotificationPermission() {
        guard canNotify else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notifyBroken() {
        guard canNotify, UserDefaults.standard.bool(forKey: Self.notifyKey) else { return }
        let content = UNMutableNotificationContent()
        content.title = "DNS is broken"
        content.body = "Click the DNS Doctor icon to repair."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "dns-broken", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in } // silently ignored if denied
    }

    // MARK: Diagnostics

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    func diagnosticsText() -> String {
        func mark(_ ok: Bool) -> String { ok ? "[ok]" : "[!!]" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .medium

        var lines: [String] = []
        lines.append("DNS Doctor \(Self.appVersion)")
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let build = ProcessInfo.processInfo.operatingSystemVersionString
            .components(separatedBy: "Build ").last?.trimmingCharacters(in: CharacterSet(charactersIn: ")")) ?? ""
        lines.append("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)\(build.isEmpty ? "" : " (\(build))")")
        lines.append("Status: \(health.title)")
        if let diagnosis { lines.append("Diagnosis: \(diagnosis)") }
        lines.append("")

        lines.append("Checks:")
        for r in dnsResults { lines.append("  \(mark(r.ok)) \(r.name) — \(r.detail)") }
        if let net = internetResult { lines.append("  \(mark(net.ok)) \(net.name) — \(net.detail)") }
        if dnsResults.isEmpty && internetResult == nil { lines.append("  (not run yet)") }
        lines.append("")

        lines.append("DNS servers in use:")
        if serverResults.isEmpty {
            lines.append("  (none configured)")
        } else {
            for r in serverResults { lines.append("  \(mark(r.ok)) \(r.name) — \(r.detail)") }
        }
        lines.append("")

        lines.append("Manual DNS per network service:")
        if manualDNS.isEmpty {
            lines.append("  (none; all services use automatic DNS)")
        } else {
            for m in manualDNS { lines.append("  \(m.service): \(m.servers.joined(separator: ", "))") }
        }
        lines.append("")

        lines.append("Public DNS mode: \(usingPublicDNS ? "on (Cloudflare + Google)" : "off")")
        lines.append("Last checked: \(lastChecked.map { f.string(from: $0) } ?? "never")")
        return lines.joined(separator: "\n")
    }
}
