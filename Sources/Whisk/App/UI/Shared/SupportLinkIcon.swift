// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit

enum SupportLinkIcon {
    private static let afdian = load("Afdian")
    private static let patreon = load("Patreon")

    static func image(for destination: URL) -> NSImage? {
        switch destination.host?.lowercased() {
        case "afdian.com", "www.afdian.com": afdian
        case "patreon.com", "www.patreon.com": patreon
        default: nil
        }
    }

    private static func load(_ name: String) -> NSImage? {
        AppResources.bundle.url(forResource: name, withExtension: "svg")
            .flatMap(NSImage.init(contentsOf:))
    }
}
