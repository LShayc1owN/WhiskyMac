// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct HoverPrivacy {
    @Test func old_preferences_migrate_and_hover_has_no_export_actions() throws {
        for action in CardAction.allCases {
            let json = Data("{\"hover\":\"\(action.rawValue)\"}".utf8)
            let migrated = try JSONDecoder().decode(InteractionBindings.self, from: json)
            #expect(migrated.hover == (action == .preview ? .preview : .none))
            #expect(migrated.hoverDelay == 0.7)
        }
        var bindings = InteractionBindings()
        bindings.hover = .paste
        #expect(bindings.hover == .none)
        bindings.hoverDelay = .nan
        #expect(bindings.hoverDelay == 0.7)
        bindings.hoverDelay = -1
        #expect(bindings.hoverDelay == 0.1)
        bindings.hoverDelay = 100
        #expect(bindings.hoverDelay == 5)
        let sandbox = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        settings.interactions = InteractionBindings(hover: .preview, hoverDelay: 1.3)
        #expect(GeneralSettingsStore(defaults: sandbox.defaults).interactions == settings.interactions)
    }

    @Test func automatic_protection_revokes_spotlight_even_if_manual_protection_stays_on() throws {
        let sandbox = try IsolatedDefaults()
        let privacy = PrivacyController(defaults: sandbox.defaults, schedulesTimer: false)
        let state = HistoryViewStateStore()
        privacy.willChangeSpotlight = { state.setSpotlightAllowed($0) }
        privacy.willChangeProtection = { state.setPrivacy($0) }
        privacy.setProtected(true)
        #expect(privacy.allowsSpotlight && state.allowsSpotlight)
        privacy.setAutomaticEnabled(true)
        #expect(privacy.isProtected && privacy.isManuallyProtected)
        #expect(!privacy.allowsSpotlight && !state.allowsSpotlight)
        privacy.receive([SharingReport(state: .active, reason: .toolbarPresent)])
        #expect(!privacy.allowsSpotlight)
        privacy.receive([SharingReport(state: .unknown, reason: .unavailable)])
        #expect(!privacy.allowsSpotlight)
        privacy.setAutomaticEnabled(false)
        #expect(privacy.allowsSpotlight)
        privacy.setProtected(false)
        #expect(!privacy.allowsSpotlight)
    }

    @Test func payload_access_requires_manual_allowance_visible_panel_and_preview_hover() {
        let state = HistoryViewStateStore()
        let item = anItem(.text("HOVER-CANARY"))
        state.update(HistoryPresenter().present(items: [item], query: "", now: item.copiedAt))
        var reads = 0
        state.detailSource = { _ in
            reads += 1; return item
        }
        state.setPrivacy(true)
        state.setSpotlightAllowed(true)
        state.setPanelVisible(true)
        #expect(state.state.cards.isEmpty)
        #expect(state.spotlightPayload(for: item.id) == nil)
        state.interactions.hover = .preview
        #expect(state.spotlightPayload(for: item.id) == item.payload)
        #expect(reads == 1)
        #expect(state.previewItems.isEmpty)
        #expect(state.spotlightPayload(for: UUID()) == nil)
        state.setSpotlightAllowed(false)
        #expect(state.spotlightPayload(for: item.id) == nil)
        state.setSpotlightAllowed(true)
        state.panelDidClose()
        #expect(state.spotlightPayload(for: item.id) == nil)
        #expect(reads == 1)
    }

    @Test func spotlight_pixels_outside_the_pointer_region_are_transparent() throws {
        let content = SpotlightCanvas(
            payload: .text(String(repeating: "SYNTHETIC SAMPLE\n", count: 12)),
            point: CGPoint(x: 110, y: 110)
        )
        .frame(width: 220, height: 220)
        let renderer = ImageRenderer(content: content)
        let image = try #require(renderer.nsImage)
        let data = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: data))
        #expect(try #require(bitmap.colorAt(x: 0, y: 0)).alphaComponent == 0)
        #expect(try #require(bitmap.colorAt(x: 110, y: 110)).alphaComponent > 0.9)
        #expect(try #require(bitmap.colorAt(x: 200, y: 110)).alphaComponent == 0)
        if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"] {
            let directory = URL(fileURLWithPath: output)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(
                to: directory.appendingPathComponent("manual-spotlight.png"))
        }
    }

    @Test func spotlight_draws_bounded_content_and_protected_host_keeps_ax_hidden() throws {
        _ = NSApplication.shared
        for payload: Payload in [
            .text("HOVER-CANARY"), .link(URL(string: "https://example.invalid")!),
            .fileReferences(["/synthetic/file.txt"]), .image(Data()),
        ] {
            let renderer = ImageRenderer(
                content: SpotlightCanvas(payload: payload, point: CGPoint(x: 100, y: 100))
                    .frame(width: 220, height: 220))
            #expect(renderer.nsImage != nil)
        }
        #expect(SpotlightCanvas.thumbnail(Data([0])) == nil)
        #expect(SpotlightCanvas.thumbnail(Data(count: 8 * 1024 * 1024 + 1)) == nil)
        #expect(SpotlightCanvas.thumbnail(ViewFixtures.png) != nil)
        let state = HistoryViewStateStore()
        state.interactions.hover = .preview
        state.setSpotlightAllowed(true)
        state.setPanelVisible(true)
        state.setPrivacy(true)
        state.update(HistoryPresenter().present(items: [anItem(.text("HOVER-CANARY"))], query: "", now: Date()))
        let host = HistoryPanelHosting.make(store: state, actions: PanelActionSpy().actions)
        #expect(host.accessibilityChildren()?.isEmpty == true)
        #expect(host.accessibilityLabel() == localized("Content hidden by Privacy Mode"))
        let renderer = ImageRenderer(content: PrivacySpotlightView(store: state))
        renderer.proposedSize = ProposedViewSize(width: 800, height: 340)
        #expect(renderer.nsImage != nil)
    }
}
