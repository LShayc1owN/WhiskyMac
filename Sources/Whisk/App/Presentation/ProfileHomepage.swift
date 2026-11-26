// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

struct ProfileHomepage: Identifiable {
    let title: String
    let destination: URL
    var id: URL { destination }

    private static let buyMeACoffee = ProfileHomepage(
        title: "Buy Me a Coffee", destination: URL(string: "https://buymeacoffee.com/funclinkrev")!)

    private static let patreon = ProfileHomepage(
        title: "Patreon",
        destination: URL(string: "https://www.patreon.com/LShayc1owN/posts/support-zhi-chi-176282716")!)

    private static var afdian: ProfileHomepage {
        ProfileHomepage(title: localized("Afdian"), destination: URL(string: "https://afdian.com/a/LShayc1owN")!)
    }

    static func supportHomepages(for distribution: Distribution) -> [ProfileHomepage] {
        if distribution == .appStore { return [buyMeACoffee] }
        return [patreon, afdian, buyMeACoffee]
    }

    static var developerHomepages: [ProfileHomepage] {
        [
            ProfileHomepage(
                title: localized("Lin Shay on GitHub"),
                destination: URL(string: "https://github.com/LShayc1owN")!),
            buyMeACoffee,
        ]
    }
}
