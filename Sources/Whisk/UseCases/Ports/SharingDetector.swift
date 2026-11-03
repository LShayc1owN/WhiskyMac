// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

/// A negative observation is scoped to this provider, never a system-wide
/// assurance. Private implementations need separate authorization.
enum SharingDetectionState: Equatable {
    case active
    case clearWithinCoverage
    case unknown
}

enum SharingDetectorKind {
    case publicAPI
    case experimental
    case manual
}

enum SharingDetectionReason: Equatable {
    case toolbarPresent
    case noMatchingToolbar
    case accessibilityRequired
    case unavailable
    case checking
}

struct SharingReport: Equatable {
    let state: SharingDetectionState
    let reason: SharingDetectionReason
}

protocol SharingDetector {
    var kind: SharingDetectorKind { get }
    func sample() -> SharingReport
}
