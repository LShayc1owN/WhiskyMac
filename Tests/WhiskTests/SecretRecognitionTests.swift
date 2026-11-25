// WhiskyMac: added 2026-11-24 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Testing

@testable import Whisk

@MainActor
@Suite struct SecretRecognitionTests {
    private static let key = "sk-test_ABCDEFGH-PRIVATE-CANARY"

    @Test(arguments: [
        "sk-test_ABCDEFGH-PRIVATE-CANARY",
        "sk_live_SAMPLE123456789",
        "ghp_SAMPLE123456789abcdef",
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ0ZXN0In0.notASignature",
        "Authorization: Bearer sample_123456789abcdefgh",
        "Cookie: preference=private-test; theme=dark",
        "Set-Cookie: id=test-value; HttpOnly",
        "session_id=sample-1234567890",
        "https://example.invalid/?access_token=example0123456789",
        "0123456789abcdef0123456789abcdef",
        "-----BEGIN PRIVATE KEY-----\nsynthetic sample",
    ])
    func recognizes_common_secret_formats(_ text: String) throws {
        let match = try #require(SecretMatch.detect(text))
        #expect(text.hasPrefix(match.visiblePrefix))
        #expect(match.visiblePrefix.count <= text.count / 5)
        #expect(match.maskedText.hasSuffix("••••••••"))
    }

    @Test(arguments: [
        "ordinary short password",
        "sk-short",
        "ask-for-a-clipboard-example",
        "#aabbcc",
        "/Users/demo/Project files",
        "https://example.invalid/help?tab=usage",
        "2f0910ce-bbe9-4230-8d4b-f3a94865d8eb",
        "This text discusses Cookie and Bearer token syntax.",
    ])
    func leaves_ordinary_clipboard_content_alone(_ text: String) {
        #expect(SecretMatch.detect(text) == nil)
    }

    @Test func mask_uses_graphemes_and_caps_credentials_in_a_long_record() throws {
        let sample = "👩🏽‍💻e\u{301} prefix \(Self.key)"
        let match = try #require(SecretMatch.detect(sample))
        #expect(match.visiblePrefix == String(sample.prefix(sample.count / 5)))
        let long = Self.key + "\n" + String(repeating: "ordinary context ", count: 5_000)
        #expect(SecretMatch.detect(long)?.visiblePrefix == String(Self.key.prefix(Self.key.count / 5)))
        #expect(SecretMatch.detect(String(repeating: "a", count: 65_537) + " " + Self.key) == nil)
    }

    @Test func preferences_are_independent_and_default_on() throws {
        let defaults = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: defaults.defaults)
        #expect(settings.secretRecognition == SecretRecognition())
        settings.secretRecognition.enabled = false
        settings.secretRecognition.classify = false
        let saved = GeneralSettingsStore(defaults: defaults.defaults)
        #expect(saved.secretRecognition == SecretRecognition(enabled: false, mask: true, classify: false))
        saved.secretRecognition.enabled = true
        #expect(saved.secretRecognition.mask && !saved.secretRecognition.classify)
        let entries = SettingsSearchIndex.entries(context: SettingsSearchContext(recognizesSecrets: false))
        #expect(entries.filter { $0.section == .secretRecognition }.contains { $0.id == "recognizeSecrets" })
        #expect(!entries.contains { $0.id == "maskSecrets" || $0.id == "classifySecrets" })
    }

    @Test func presentation_contains_only_masked_content_and_original_source() throws {
        let item = ClipboardItem(
            id: UUID(), payload: .text(Self.key), source: SourceApp(name: "Fixture App", bundleID: "fixture.app"),
            copiedAt: Date(), isPinned: false, rtf: Data(Self.key.utf8))
        let presenter = HistoryPresenter()
        let view = presenter.present(items: [item], query: "PRIVATE", now: item.copiedAt)
        let card = try #require(view.cards.first)
        let prefix = String(Self.key.prefix(Self.key.count / 5))
        #expect(card.preview == .text(prefix + "••••••••"))
        #expect(card.sourceLabel == "Fixture App" && card.sourceBundleID == "fixture.app")
        #expect(card.kindSymbol == ContentCategory.secret.symbolName && card.contentHidden && card.secretMasked)
        #expect(!card.accessibilityLabel.contains("PRIVATE") && card.accessibilityLabel.contains(prefix))
        #expect(card.dragPayload == .text("") && card.richText == nil && card.matches.isEmpty)
        #expect(card.detailLabel == nil && !card.saveable && !card.transformable)
        #expect(presenter.cachedPreviewCount == 0)
        let commands = CardMenuCommand.sections(for: card).flatMap { $0 }
        #expect(commands.contains(.revealSecret))
        #expect(!commands.contains(.preview) && !commands.contains(.edit) && !commands.contains(.split))

        let unclassified = presenter.present(
            items: [item], query: "", now: item.copiedAt, recognition: SecretRecognition(classify: false))
        #expect(unclassified.cards.first?.kindSymbol == item.category.symbolName)
        #expect(unclassified.cards.first?.secretMasked == true)
        let unmasked = presenter.present(
            items: [item], query: "", now: item.copiedAt, recognition: SecretRecognition(mask: false))
        #expect(unmasked.cards.first?.dragPayload == .text(Self.key))
        #expect(unmasked.cards.first?.kindSymbol == ContentCategory.secret.symbolName)
        #expect(unmasked.cards.first?.secretMasked == false)
    }

    @Test func filtering_and_history_hiding_share_the_current_classification() {
        let item = anItem(.text(Self.key), from: "Fixture App", bundle: "fixture.app")
        let history = History(items: [item])
        let filter = FilterHistory()
        #expect(filter(history, filter: HistoryFilter(categories: [.secret])) == [item])
        for mode in SearchMatchMode.allCases {
            #expect(
                filter(history, filter: HistoryFilter(query: "type:secret PRIVATE-CANARY", searchMatchMode: mode))
                    .isEmpty)
        }
        #expect(filter(history, filter: HistoryFilter(query: "type:secret app:fixture")) == [item])
        #expect(
            filter(history, filter: HistoryFilter(query: "PRIVATE-CANARY"), recognition: SecretRecognition(mask: false))
                == [item])
        let hiding = HistoryHidingRule(cutoff: item.copiedAt, categories: [.secret])
        #expect(hiding.hides(item))
        #expect(!hiding.hides(item, recognition: SecretRecognition(classify: false)))

        let board = ScriptedPasteboard()
        let disk = InMemoryHistoryStore()
        disk.stored = [item]
        let state = HistoryViewStateStore()
        let controller = ClipboardController(pasteboard: board, store: disk, clock: FakeClock()) { state.update($0) }
        #expect(state.state.filters.kinds.map(\.id) == ["secret"])
        controller.setHistoryHiding(hiding)
        #expect(state.state.cards.isEmpty)
        controller.setSecretRecognition(SecretRecognition(enabled: false))
        #expect(state.state.cards.first?.preview == .text(Self.key))
        #expect(!state.state.filters.kinds.contains { $0.id == "secret" })
        #expect(disk.stored == [item] && disk.saveCount == 0)
    }

    @Test func explicit_reveal_closes_on_edit_removal_protection_and_panel_hide() {
        let item = anItem(.text(Self.key))
        let changed = item.replacing(payload: .text("sk-SYNTHETIC_DIFFERENT_VERSION"))
        let pinned = item.withPinnedMetadata(PinnedMetadata(hidesContent: true))
        let store = HistoryViewStateStore()
        let presenter = HistoryPresenter()
        var current: ClipboardItem? = item
        store.detailSource = { _ in current }
        func update(_ item: ClipboardItem?) {
            current = item
            store.update(presenter.present(items: item.map { [$0] } ?? [], query: "", now: Date()))
        }
        update(item)
        store.revealSecret(item.id)
        #expect(store.revealedSecret == nil)
        store.setPanelVisible(true)
        store.revealSecret(item.id)
        #expect(store.revealedSecret == Self.key && store.hasAuxiliaryContent)
        update(changed)
        #expect(store.revealedSecret == nil && !store.hasAuxiliaryContent)
        store.revealSecret(changed.id)
        #expect(store.revealedSecret == changed.payload.transformableText)
        update(nil)
        #expect(store.revealedSecret == nil)
        update(pinned)
        store.revealSecret(pinned.id)
        #expect(store.revealedSecret == nil)
        update(item)
        store.revealSecret(item.id)
        store.setPrivacy(true)
        store.setSpotlightAllowed(true)
        #expect(store.revealedSecret == nil && store.protectedRevealPayload(for: item.id) == nil)
        store.revealSecret(item.id)
        #expect(store.revealedSecret == nil)
        store.setPrivacy(false)
        store.revealSecret(item.id)
        store.setPanelVisible(false)
        #expect(store.revealedSecret == nil)
    }

    @Test func credential_links_and_split_children_cannot_leak_in_previews() throws {
        let url = try #require(URL(string: "https://example.invalid/?token=SYNTHETIC123456789abcdefgh"))
        let link = anItem(.link(url))
        let part = SplitPart(id: UUID(), text: "ordinary link label", link: url, rtf: nil)
        let groupItem = anItem(.text("Original group body")).withSplitGroup(SplitGroup(parts: [part], plainText: false))
        let board = ScriptedPasteboard()
        let disk = InMemoryHistoryStore()
        disk.stored = [link, groupItem]
        let state = HistoryViewStateStore()
        let controller = ClipboardController(pasteboard: board, store: disk, clock: FakeClock()) { state.update($0) }
        #expect(controller.hiddenLinkAddresses == [url.absoluteString])
        #expect(state.state.cards.map(\.secretMasked) == [true, true])
        let selector = SplitGroupSession(
            source: groupItem, action: .copy, plain: false, query: part.text, hideContent: true,
            current: { _ in groupItem }, allowed: { true }, export: { _, _, _, _, _ in })
        #expect(selector.hidesContent && !selector.matches(part))
        controller.setSecretRecognition(SecretRecognition(mask: false))
        #expect(controller.hiddenLinkAddresses == [url.absoluteString])
        controller.setSecretRecognition(SecretRecognition(enabled: false))
        #expect(controller.hiddenLinkAddresses.isEmpty)
    }
}
