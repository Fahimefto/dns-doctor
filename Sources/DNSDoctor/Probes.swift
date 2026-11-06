import Foundation
import Network

/// Makes sure a continuation is resumed only once when a probe races a timeout.
final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

enum Probes {
    /// Resolves a hostname through the system resolver (mDNSResponder), the same
    /// path every app on the Mac uses. Returns the lookup time, or nil if it failed or timed out.
    static func resolve(_ host: String, timeout: TimeInterval = 4) async -> TimeInterval? {
        await withCheckedContinuation { cont in
            let once = OnceFlag()
            let start = Date()
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                let rc = getaddrinfo(host, nil, &hints, &result)
                if let result { freeaddrinfo(result) }
                if once.claim() {
                    cont.resume(returning: rc == 0 ? Date().timeIntervalSince(start) : nil)
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() { cont.resume(returning: nil) }
            }
        }
    }

    /// Opens a TCP connection straight to an IP address (no DNS involved),
    /// to tell "DNS is broken" apart from "there's no internet at all".
    static func reachable(_ ip: String, port: UInt16, timeout: TimeInterval = 4) async -> Bool {
        await withCheckedContinuation { cont in
            let once = OnceFlag()
            let conn = NWConnection(host: NWEndpoint.Host(ip),
                                    port: NWEndpoint.Port(rawValue: port)!,
                                    using: .tcp)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { conn.cancel(); cont.resume(returning: true) }
                case .failed, .cancelled:
                    if once.claim() { conn.cancel(); cont.resume(returning: false) }
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.claim() { conn.cancel(); cont.resume(returning: false) }
            }
        }
    }

    /// DNS servers macOS is currently using, read from `scutil --dns`.
    static func currentNameservers() -> [String] {
        guard let output = run("/usr/sbin/scutil", ["--dns"]) else { return [] }
        // Only the main section; the "scoped queries" section repeats per-interface servers.
        let main = output.components(separatedBy: "DNS configuration (for scoped queries)").first ?? output
        var seen = Set<String>()
        var servers: [String] = []
        for line in main.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("nameserver["),
                  let value = trimmed.split(separator: ":", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces),
                  !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            servers.append(value)
        }
        return servers
    }

    /// Asks one specific DNS server directly with `dig`, bypassing the system resolver.
    /// Tells "mDNSResponder is stuck" apart from "the server itself is dead".
    /// Synchronous and blocking (up to ~4 s); call it off the main thread.
    /// Scoped IPv6 servers such as `fe80::1%en0` are passed through as-is; dig accepts them.
    static func queryServer(_ server: String, host: String = "apple.com") -> Bool {
        let args = ["@\(server)", host, "+time=2", "+tries=1", "+short"]
        guard let out = run("/usr/bin/dig", args, timeout: 4) else { return false }
        // On failure dig still prints ";; connection timed out" style lines; only count real addresses.
        return out.split(separator: "\n").contains { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            return !s.isEmpty && !s.hasPrefix(";") && isIPAddress(s)
        }
    }

    static func isIPAddress(_ s: String) -> Bool {
        var v4 = in_addr()
        var v6 = in6_addr()
        return inet_pton(AF_INET, s, &v4) == 1 || inet_pton(AF_INET6, s, &v6) == 1
    }

    /// Runs a command and returns its stdout. With `timeout`, the process is killed
    /// after that many seconds so a hung tool can never stall a check.
    static func run(_ path: String, _ args: [String], timeout: TimeInterval? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }

        var killer: DispatchWorkItem?
        if let timeout {
            let pid = process.processIdentifier
            let item = DispatchWorkItem { if process.isRunning { kill(pid, SIGKILL) } }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
            killer = item
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer?.cancel()
        return String(data: data, encoding: .utf8)
    }

    /// Runs blocking work (process spawns, getaddrinfo) on a GCD queue instead of
    /// Swift's small cooperative thread pool, so several probes can block at once.
    static func background<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async { cont.resume(returning: work()) }
        }
    }
}
