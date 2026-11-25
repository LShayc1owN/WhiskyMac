// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

struct ProfileHomepage: Identifiable {
    let title: String
    let destination: URL
    var id: URL { destination }

    static var developerHomepages: [ProfileHomepage] {
        [
            ProfileHomepage(
                title: localized("Lin Shay on GitHub"),
                destination: URL(string: "https://github.com/LShayc1owN")!),
            ProfileHomepage(
                title: "Buy Me a Coffee", destination: URL(string: "https://buymeacoffee.com/funclinkrev")!),
        ]
    }
}
