// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ApplicationServices
import Combine

enum OnboardingPage: Int, CaseIterable, Identifiable {
    // Declaration order drives navigation. Raw values are persisted.
    case welcome = 0
    case basicSettings = 8
    case permissions = 1
    case practice = 2
    case tools = 3
    case privacy = 4
    case preferences = 5
    case guide = 6
    case ready = 7

    var id: Int { rawValue }
    static let steps = Array(allCases.dropFirst())

    var stepNumber: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    func advanced(by offset: Int) -> Self? {
        let destination = stepNumber + offset
        return Self.allCases.indices.contains(destination) ? Self.allCases[destination] : nil
    }

    static var welcomeTitle: String { localized("Make room for your next idea.") }

    var label: String {
        switch self {
        case .welcome: localized("Welcome")
        case .basicSettings: localized("Basic settings")
        case .permissions: localized("Permissions")
        case .practice: localized("Try it out")
        case .tools: localized("Everyday tools")
        case .privacy: localized("Privacy")
        case .preferences: localized("More settings and configuration")
        case .guide: localized("Quick reference")
        case .ready: localized("All set")
        }
    }

}

final class OnboardingState: ObservableObject {
    @Published private(set) var page: OnboardingPage
    @Published private(set) var clipboardAccess: PasteboardAccess = .requiresConsent
    @Published private(set) var accessibilityGranted = false
    private let defaults: UserDefaults
    private let readClipboardAccess: () -> PasteboardAccess
    private let readAccessibility: () -> Bool

    init(
        defaults: UserDefaults = AppIdentity.defaults,
        readClipboardAccess: @escaping () -> PasteboardAccess,
        readAccessibility: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.defaults = defaults
        self.readClipboardAccess = readClipboardAccess
        self.readAccessibility = readAccessibility
        page = OnboardingPage(rawValue: defaults.integer(forKey: "onboardingPage")) ?? .welcome
    }

    func select(_ page: OnboardingPage) {
        self.page = page
        defaults.set(page.rawValue, forKey: "onboardingPage")
        refreshPermissions()
    }

    func move(_ offset: Int) {
        guard let next = page.advanced(by: offset) else { return }
        select(next)
    }

    /// Replay the guide without changing whether first-run setup was completed.
    func restart() {
        select(.welcome)
    }

    func refreshPermissions() {
        let access = readClipboardAccess()
        let trusted = readAccessibility()
        if clipboardAccess != access { clipboardAccess = access }
        if accessibilityGranted != trusted { accessibilityGranted = trusted }
    }

    func complete() {
        defaults.set(true, forKey: "didShowOnboarding")
        defaults.removeObject(forKey: "onboardingPage")
    }
}

struct OnboardingActions {
    var allowClipboard: () -> Void = {}
    var allowAccessibility: () -> Void = {}
    var openSettings: (SettingsDestination) -> Void = { _ in }
    var later: () -> Void = {}
    var finish: () -> Void = {}
}
