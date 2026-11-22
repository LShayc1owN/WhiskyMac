// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ApplicationServices
import Combine

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome, permissions, practice, tools, privacy, preferences, guide, ready
    var id: Int { rawValue }
    static let steps = Array(allCases.dropFirst())

    static var welcomeTitle: String { localized("Make room for your next idea.") }

    var label: String {
        switch self {
        case .welcome: localized("Welcome")
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
    let practice = OnboardingPracticeSession()
    private var practiceObserver: AnyCancellable?

    var isPracticeComplete: Bool { practice.isComplete }
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
        practiceObserver = practice.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
    }

    func select(_ page: OnboardingPage) {
        if self.page != page { practice.cancelTransient() }
        self.page = page
        defaults.set(page.rawValue, forKey: "onboardingPage")
        refreshPermissions()
    }

    func move(_ offset: Int) {
        guard let next = OnboardingPage(rawValue: page.rawValue + offset) else { return }
        select(next)
    }

    /// Replay the guide without changing whether first-run setup was completed.
    func restart() {
        practice.reset()
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
