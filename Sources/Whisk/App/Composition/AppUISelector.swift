// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Select once during assembly and inject that factory into every coordinator.
@MainActor
enum AppUISelector {
    static func make() -> any AppUIFactory {
        if #available(macOS 26, *) {
            MacOS26UIFactory()
        } else {
            MacOS15UIFactory()
        }
    }
}
