import Foundation

/// Reads macOS network service settings via `networksetup` (no admin rights needed to read).
enum NetworkServices {
    struct ServiceDNS: Equatable {
        let service: String
        let servers: [String] // empty = automatic (from DHCP / router)
    }

    /// Enabled network services, e.g. ["Wi-Fi", "USB 10/100/1000 LAN", "Thunderbolt Bridge"].
    static func enabledServices() -> [String] {
        guard let out = Probes.run("/usr/sbin/networksetup", ["-listallnetworkservices"]) else { return [] }
        return out.split(separator: "\n")
            .map(String.init)
            .dropFirst() // "An asterisk (*) denotes that a network service is disabled."
            .filter { !$0.hasPrefix("*") && !$0.isEmpty }
    }

    static func dnsServers(for service: String) -> [String] {
        guard let out = Probes.run("/usr/sbin/networksetup", ["-getdnsservers", service]) else { return [] }
        if out.contains("aren't any") || out.contains("not a recognized") { return [] }
        return out.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains(" ") }
    }

    /// Services that have DNS servers typed in manually (instead of automatic).
    static func manualDNS() -> [ServiceDNS] {
        enabledServices().compactMap { svc in
            let servers = dnsServers(for: svc)
            return servers.isEmpty ? nil : ServiceDNS(service: svc, servers: servers)
        }
    }

    /// BSD device names (en0, en5…) of enabled services that currently have an IPv4
    /// address and get it from DHCP. Renewing these refreshes the router-provided DNS.
    static func activeDHCPInterfaces() -> [String] {
        guard let order = Probes.run("/usr/sbin/networksetup", ["-listnetworkserviceorder"]) else { return [] }
        var result: [String] = []
        var currentService: String?
        for line in order.split(separator: "\n").map(String.init) {
            if line.hasPrefix("("), let close = line.firstIndex(of: ")"), !line.hasPrefix("(Hardware") {
                currentService = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            } else if line.contains("Device: "), let svc = currentService,
                      let devPart = line.components(separatedBy: "Device: ").last {
                let dev = devPart.trimmingCharacters(in: CharacterSet(charactersIn: ") "))
                guard !dev.isEmpty, !svc.hasPrefix("*") else { continue }
                let addr = Probes.run("/usr/sbin/ipconfig", ["getifaddr", dev])?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !addr.isEmpty else { continue }
                let info = Probes.run("/usr/sbin/networksetup", ["-getinfo", svc]) ?? ""
                if info.contains("DHCP Configuration") { result.append(dev) }
            }
        }
        return result
    }
}
