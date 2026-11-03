// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

/// Best-effort capture attribution. A Handoff marker carries no verified
/// source device or application; ordinary entries name the observed Mac app.
struct SourceApp: Equatable, Hashable {
    enum Origin: String {
        case observedApplication
        case handoffMarker
    }
    let origin: Origin
    let name: String?
    let bundleID: String?

    init?(name: String?, bundleID: String? = nil, origin: Origin = .observedApplication) {
        guard name != nil || bundleID != nil || origin == .handoffMarker else { return nil }
        self.origin = origin
        self.name = origin == .handoffMarker ? nil : name
        self.bundleID = origin == .handoffMarker ? nil : bundleID
    }

    /// Stable identity for filtering; the invariant guarantees one field.
    var filterKey: String {
        origin == .handoffMarker ? "origin:handoff-marker" : (bundleID ?? name ?? "")
    }

    /// Lenient identity: items recorded before the bundle id existed carry
    /// a name only, and must still count as the same application.
    func matches(_ other: SourceApp) -> Bool {
        guard origin == other.origin else { return false }
        if origin == .handoffMarker { return true }
        if let mine = bundleID, let theirs = other.bundleID {
            return mine == theirs
        }
        return name != nil && name == other.name
    }
}
