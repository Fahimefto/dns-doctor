import Foundation

enum RepairResult {
    case success
    case cancelled
    case failure(String)
}

/// All fixes that need admin rights. Each runs through the standard macOS admin
/// prompt (password or Touch ID). Nothing is installed or left running as root.
enum DNSRepair {
    static let publicDNS = ["1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4"]
    private static let savedKey = "savedDNSBeforePublic"

    /// Level 1, same as the `cdnfix` alias: flush the cache and reload mDNSResponder.
    static func quickFix() async -> RepairResult {
        await runPrivileged(flushCommands)
    }

    struct DeepPlan {
        var resetServices: [String] = []   // manual DNS servers that don't answer
        var renewInterfaces: [String] = [] // DHCP interfaces to renew
    }

    /// Works out the deep fix without admin rights: which manually-set DNS servers are
    /// dead (typically left behind by a VPN) and which interfaces can renew their lease.
    static func planDeepFix() async -> DeepPlan {
        await Task.detached {
            var plan = DeepPlan()
            let usingPublic = UserDefaults.standard.dictionary(forKey: savedKey) != nil
            for entry in NetworkServices.manualDNS() {
                // Leave the servers alone if any of them still answers; the user may want them.
                var anyAlive = false
                for server in entry.servers where Probes.queryServer(server) { anyAlive = true; break }
                if !anyAlive && !usingPublic { plan.resetServices.append(entry.service) }
            }
            plan.renewInterfaces = NetworkServices.activeDHCPInterfaces()
            return plan
        }.value
    }

    /// Level 2: restart mDNSResponder completely, clear dead manual DNS servers back to
    /// automatic, and renew DHCP so the router hands out fresh DNS servers.
    static func deepFix(_ plan: DeepPlan) async -> RepairResult {
        var cmds = [
            "/usr/bin/killall mDNSResponder mDNSResponderHelper 2>/dev/null; true",
            "sleep 1",
        ]
        for svc in plan.resetServices {
            cmds.append("/usr/sbin/networksetup -setdnsservers \(shellQuote(svc)) empty")
        }
        for dev in plan.renewInterfaces {
            cmds.append("/usr/sbin/ipconfig set \(shellQuote(dev)) DHCP")
        }
        cmds.append(contentsOf: flushCommands)
        return await runPrivileged(cmds)
    }

    // MARK: Public DNS fallback

    static var isUsingPublicDNS: Bool {
        UserDefaults.standard.dictionary(forKey: savedKey) != nil
    }

    /// Points every enabled network service at Cloudflare + Google DNS, remembering the
    /// previous settings so they can be restored exactly.
    static func usePublicDNS() async -> RepairResult {
        let services = await Task.detached { NetworkServices.enabledServices() }.value
        var saved: [String: [String]] = [:]
        if !isUsingPublicDNS {
            for svc in services { saved[svc] = NetworkServices.dnsServers(for: svc) }
        }
        var cmds = services.map { svc in
            "/usr/sbin/networksetup -setdnsservers \(shellQuote(svc)) \(publicDNS.joined(separator: " "))"
        }
        cmds.append(contentsOf: flushCommands)
        let result = await runPrivileged(cmds)
        if case .success = result, !isUsingPublicDNS {
            UserDefaults.standard.set(saved, forKey: savedKey)
        }
        return result
    }

    /// Puts back whatever DNS settings each service had before "Use public DNS".
    static func restoreDNS() async -> RepairResult {
        let saved = UserDefaults.standard.dictionary(forKey: savedKey) as? [String: [String]] ?? [:]
        let current = await Task.detached { NetworkServices.enabledServices() }.value
        var cmds: [String] = []
        for svc in current {
            let previous = saved[svc] ?? []
            let value = previous.isEmpty ? "empty" : previous.map(shellQuote).joined(separator: " ")
            cmds.append("/usr/sbin/networksetup -setdnsservers \(shellQuote(svc)) \(value)")
        }
        cmds.append(contentsOf: flushCommands)
        let result = await runPrivileged(cmds)
        if case .success = result { UserDefaults.standard.removeObject(forKey: savedKey) }
        return result
    }

    // MARK: Plumbing

    private static let flushCommands = [
        "/usr/bin/dscacheutil -flushcache",
        "/usr/bin/killall -HUP mDNSResponder",
    ]

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func runPrivileged(_ commands: [String]) async -> RepairResult {
        let shell = commands.joined(separator: "; ")
        let prompt = "DNS Doctor needs your password to repair DNS."
        let script = "do shell script \"\(appleScriptEscape(shell))\" with prompt \"\(prompt)\" with administrator privileges"
        return await Task.detached(priority: .userInitiated) { () -> RepairResult in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()
            do { try process.run() } catch { return .failure(error.localizedDescription) }
            process.waitUntilExit()
            if process.terminationStatus == 0 { return .success }
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if err.contains("-128") || err.localizedCaseInsensitiveContains("cancel") { return .cancelled }
            return .failure(err.trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }
}
