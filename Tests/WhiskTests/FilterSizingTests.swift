// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI
import Testing
import Vision

@testable import Whisk

@MainActor
@Suite(.serialized) struct FilterSizingTests {
    private final class Model: ObservableObject {
        @Published var scale = 1.0
        @Published var focus: String?
        @Published var active: String?
        let scope = FilterAppScope(visibleSourceKeys: ["app.whisk"])

        var filters: FilterBarViewState {
            func chip(_ id: String, _ title: String, _ icon: String? = nil) -> FilterChip {
                FilterChip(
                    id: id, label: title, sourceBundleID: nil, icon: icon.map(ChipIcon.symbol),
                    accessibilityLabel: title, isActive: active == id, isFocused: focus == id)
            }
            return FilterBarViewState(
                all: [chip(allFiltersChipID, localized("All"), "square.grid.2x2")],
                pinned: [chip(pinnedChipID, localized("Pinned items"), "pin.fill")],
                apps: [
                    chip("app.whisk", "Whisk"), chip("app.edge", "Microsoft Edge"),
                    chip("app.github", "GitHub Desktop"),
                    chip("app.long", String(repeating: "Very Long Application Name ", count: 5)),
                ],
                kinds: [chip("text", localized("Text"), "text.alignleft"), chip("image", localized("Image"), "photo")])
        }
    }

    private struct Row: View {
        @ObservedObject var model: Model
        var body: some View {
            FilterBarView(
                filters: model.filters, tagScale: model.scale, appScope: model.scope,
                onToggleApp: { _ in }, onToggleKind: { _ in }, onFocusApp: { _ in }, onFocusKind: { _ in }
            )
            .environment(\.colorScheme, .dark)
            .transaction { $0.disablesAnimations = true }
        }
    }

    @Test func full_labels_survive_live_scaling_expansion_and_selection_in_all_supported_languages() async throws {
        _ = NSApplication.shared
        let previousLanguage = AppLocalization.language
        defer { AppLocalization.language = previousLanguage }
        for language in ["zh-Hans", "zh-Hant", "en", "fr", "de", "it", "ja"] {
            AppLocalization.language = language
            let model = Model()
            let host = NSHostingView(rootView: Row(model: model))
            host.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(x: -10000, y: -10000, width: 320, height: 70),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFront(nil)
            defer { window.contentView = nil; window.close() }
            for scale in [0.75, 1, 2, 1] {
                model.scale = scale
                window.setContentSize(NSSize(width: 320, height: FilterTagMetrics(scale: scale).rowHeight + 12))
                for expanded in [false, true] {
                    model.scope.isExpanded = expanded
                    model.active = "app.whisk"
                    model.focus = "app.whisk"
                    await settle(host)
                    let bitmap = try snapshot(host)
                    let whiskText = try text(in: bitmap, language: language)
                    #expect(whiskText.contains("whisk"), "\(language), \(scale), expanded=\(expanded): \(whiskText)")
                    if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"], expanded {
                        let directory = URL(fileURLWithPath: output)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try bitmap.representation(using: .png, properties: [:])?.write(
                            to: directory.appendingPathComponent("filter-\(language)-\(Int(scale * 100)).png"))
                    }
                    model.active = allFiltersChipID
                    model.focus = allFiltersChipID
                    await settle(host)
                    let firstBitmap = try snapshot(host)
                    let firstText = try text(in: firstBitmap, language: language)
                    // SF's small lowercase l can be recognized as i; both retain all three glyphs.
                    let complete =
                        firstText.contains(normalized(localized("All")))
                        || (language == "en" && firstText.contains("ail"))
                    #expect(complete, "\(language), \(scale), expanded=\(expanded): \(firstText)")
                    if let output = ProcessInfo.processInfo.environment["WHISK_UI_ARTIFACTS"], expanded {
                        try firstBitmap.representation(using: .png, properties: [:])?.write(
                            to: URL(fileURLWithPath: output).appendingPathComponent(
                                "filter-first-\(language)-\(Int(scale * 100)).png"))
                    }
                }
            }
            model.scope.isExpanded = true
            model.focus = "app.long"
            await settle(host)
            let material = descendants(host).compactMap { $0 as? BackdropView }
            #expect(material.contains { $0.bounds.width > 320 }, "Long labels must extend into horizontal scrolling")
        }
    }

    private func settle(_ host: NSView) async {
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
    }

    private func snapshot(_ host: NSView) throws -> NSBitmapImageRep {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func normalized(_ text: String) -> String { text.filter(\.isLetter).lowercased() }

    private func text(in bitmap: NSBitmapImageRep, language: String) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = [language == "en" ? "en-US" : language, "en-US"]
        try VNImageRequestHandler(cgImage: try #require(bitmap.cgImage)).perform([request])
        return normalized((request.results ?? []).flatMap { $0.topCandidates(3).map(\.string) }.joined())
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
