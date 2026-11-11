// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ApplicationServices

/// Narrow, replaceable public-API heuristic. Reads only top-level AX window
/// titles of explicitly supported processes. It never traverses documents,
/// chat, web content or menu items. These client UI contracts are not stable.
final class PublicSharingDetector: SharingDetector {
    struct Application {
        let bundleID: String
        let processID: pid_t
    }
    enum WindowRead {
        case titles([String])
        case unavailable
    }
    let kind = SharingDetectorKind.publicAPI
    private let applications: () -> [Application]
    private let trusted: () -> Bool
    private let readWindows: (pid_t) -> WindowRead
    static let supportedBundleIDs: Set<String> = ["us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2"]

    init(
        applications: @escaping () -> [Application] = {
            NSWorkspace.shared.runningApplications.compactMap { app in
                app.bundleIdentifier.map { Application(bundleID: $0, processID: app.processIdentifier) }
            }
        }, trusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        readWindows: @escaping (pid_t) -> WindowRead = PublicSharingDetector.windowTitles
    ) {
        self.applications = applications
        self.trusted = trusted
        self.readWindows = readWindows
    }

    func sample() -> SharingReport {
        let candidates = applications().filter { Self.supportedBundleIDs.contains($0.bundleID) }
        guard !candidates.isEmpty else {
            return SharingReport(state: .clearWithinCoverage, reason: .noMatchingToolbar)
        }
        guard trusted() else { return SharingReport(state: .unknown, reason: .accessibilityRequired) }
        var incomplete = false
        for app in candidates.prefix(8) {
            switch readWindows(app.processID) {
            case .unavailable: incomplete = true
            case .titles(let titles):
                if titles.contains(where: { Self.matches(bundleID: app.bundleID, title: $0) }) {
                    return SharingReport(state: .active, reason: .toolbarPresent)
                }
            }
        }
        if candidates.count > 8 { incomplete = true }
        return SharingReport(
            state: incomplete ? .unknown : .clearWithinCoverage,
            reason: incomplete ? .unavailable : .noMatchingToolbar)
    }

    static func matches(bundleID: String, title: String) -> Bool {
        switch bundleID {
        case "us.zoom.xos":
            return ["as_toolbar", "Zoom Share Statusbar Window"].contains(title)
        case "com.microsoft.teams", "com.microsoft.teams2":
            return ["Screen sharing toolbar", "Sharing control bar"].contains(title)
        default: return false
        }
    }

    private static func windowTitles(_ pid: pid_t) -> WindowRead {
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementSetMessagingTimeout(app, 0.05) == .success else { return .unavailable }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement], windows.count <= 16
        else { return .unavailable }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        var titles: [String] = []
        for window in windows {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return .unavailable }
            _ = AXUIElementSetMessagingTimeout(window, 0.05)
            var title: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            if error == .noValue || error == .attributeUnsupported { continue }
            guard error == .success else { return .unavailable }
            if let text = title as? String { titles.append(text) }
        }
        return .titles(titles)
    }
}
