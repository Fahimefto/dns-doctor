import AppKit
import Combine
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let monitor = DNSMonitor()
    private var repairObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        updateIcon(.checking)

        popover.behavior = .transient
        popover.animates = true
        let hostingController = NSHostingController(rootView: StatusView(monitor: monitor))
        hostingController.sizingOptions = .preferredContentSize // popover grows/shrinks with content
        popover.contentViewController = hostingController

        // Notifications only exist inside an .app bundle (not under `swift run`).
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }

        // The admin password dialog closes the transient popover; bring it back with the result.
        repairObserver = monitor.$isRepairing
            .removeDuplicates()
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in self?.showPopover() }

        monitor.onHealthChange = { [weak self] health in self?.updateIcon(health) }
        monitor.start()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
            Task { await monitor.check() }
        }
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateIcon(_ health: DNSHealth) {
        guard let button = statusItem.button else { return }
        button.image = StatusIcon.make(health: health, button: button)
        button.toolTip = "DNS Doctor: " + {
            switch health {
            case .checking: return "checking…"
            case .healthy: return "DNS is working"
            case .dnsBroken: return "DNS is broken"
            case .offline: return "no internet"
            }
        }()
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Show the banner even if the app counts as active (e.g. the popover was just open).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    /// Clicking the notification opens the popover so Repair is one click away.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            self.showPopover()
            completionHandler()
        }
    }
}

enum StatusIcon {
    @MainActor
    static func make(health: DNSHealth, button: NSStatusBarButton) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let symbolName = health == .offline ? "network.slash" : "network"
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "DNS Doctor")!
            .withSymbolConfiguration(config)!

        let dot: NSColor? = switch health {
        case .healthy: .systemGreen
        case .dnsBroken: .systemRed
        case .offline: .systemOrange
        case .checking: nil
        }

        guard let dot else {
            base.isTemplate = true // plain globe while checking; adapts to light/dark automatically
            return base
        }

        // Badged icon: the globe in the menu bar's text color, with a colored dot bottom-right.
        let size = NSSize(width: base.size.width + 3, height: max(base.size.height, 18))
        let image = NSImage(size: size, flipped: false) { [weak button] rect in
            let draw = {
                let tinted = base.withSymbolConfiguration(
                    NSImage.SymbolConfiguration(paletteColors: [.labelColor]))!
                let y = (rect.height - base.size.height) / 2
                tinted.draw(in: NSRect(x: 0, y: y, width: base.size.width, height: base.size.height))
                let d: CGFloat = 8
                let dotRect = NSRect(x: rect.width - d, y: 1, width: d, height: d)
                dot.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            if let appearance = button?.effectiveAppearance {
                appearance.performAsCurrentDrawingAppearance(draw)
            } else {
                draw()
            }
            return true
        }
        image.cacheMode = .never
        image.isTemplate = false
        return image
    }
}

// MARK: - Entry point

if CommandLine.arguments.dropFirst().contains("--check") {
    // CLI mode: one round of probes, a plain-text report, exit code 0/1/2.
    // No status item, popover, or notifications. The monitor is @MainActor, so the
    // work runs as a main-actor task while the main run loop services it.
    Task { @MainActor in
        let monitor = DNSMonitor()
        let health = await monitor.checkOnce()
        print(monitor.diagnosticsText())
        exit(health.exitCode)
    }
    RunLoop.main.run()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
