// WhiskyMac: modified or added 2026-11-05 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@Suite @MainActor struct StatusMenuMessageTests {
    @Test(arguments: ["en", "fr", "de", "it", "zh-Hans"])
    func localized_detection_status_wraps_in_a_fixed_width_menu_view(language: String) throws {
        let bundle = AppLocalization.selectedBundle(in: AppResources.bundle, language: language)
        let text = localized(
            "No supported toolbar detected. Other sharing or recording may still be active.",
            bundle: bundle)
        #expect(StatusMenuMessage.formattedText(text).contains("\n"))

        let item = StatusMenuMessage.item(for: text)
        let view = try #require(item.view as? NSHostingView<StatusMenuMessage>)
        #expect(view.frame.width == StatusMenuMessage.width)
        #expect(view.frame.height > 30)
        #expect(item.title.isEmpty)
    }
}
