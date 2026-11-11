// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

extension SplitRule {
    var label: String {
        switch self {
        case .lines: localized("By line")
        case .paragraphs: localized("By paragraph")
        case .delimiters: localized("By separator")
        case .links: localized("Extract links")
        }
    }
}
extension SplitSaveMode {
    var label: String {
        switch self {
        case .keepOriginal: localized("Keep original and add cards")
        case .replace: localized("Replace original card")
        case .group: localized("Save as a card group")
        }
    }
}
extension SplitDelimiter {
    var label: String {
        switch self {
        case .comma: localized("Comma (, / ，)")
        case .semicolon: localized("Semicolon (; / ；)")
        case .enumeration: localized("Enumeration comma (、)")
        case .tab: localized("Tab")
        }
    }
}

struct SplitContentView: View {

    @ObservedObject var session: SplitSession
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Split options"))
                .font(.title3)
            if session.source != nil {
                Picker(localized("Split rule"), selection: $session.options.rule) {
                    ForEach(SplitRule.allCases, id: \.rawValue) {
                        Text($0.label).tag($0)
                    }
                }

                if session.options.rule == .delimiters {
                    HStack {
                        ForEach(SplitDelimiter.allCases, id: \.rawValue) { delimiter in
                            Toggle(
                                delimiter.label,
                                isOn: Binding(
                                    get: {
                                        session.options.delimiters.contains(delimiter)
                                    },
                                    set: {
                                        if $0 {
                                            session.options.delimiters.insert(delimiter)
                                        } else {
                                            session.options.delimiters.remove(delimiter)
                                        }
                                    })
                            )
                            .toggleStyle(.checkbox)
                        }
                    }

                    TextField(localized("Custom separator (literal text)"), text: $session.options.customDelimiter)
                }
                if session.options.rule == .links {
                    Toggle(localized("Only links (off: split text and links)"), isOn: $session.options.linksOnly)
                } else {
                    Toggle(
                        localized("Keep separators at the end of the previous part"),
                        isOn: $session.options.keepDelimiter)
                }
                Toggle(localized("Trim surrounding whitespace"), isOn: $session.options.trimWhitespace)
                Toggle(localized("Plain text (discard formatting)"), isOn: $session.options.plainText)

                Divider()

                HStack {
                    Text(localized("Results"))
                        .font(.title3)
                    Text("\(session.candidates.filter(\.isSelected).count) / \(session.candidates.count)")
                        .monospacedDigit()

                    Spacer()

                    if session.analyzing {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !session.analyzing, session.candidates.isEmpty {
                            Text(localized("No split results. Try another rule."))
                        }
                        ForEach($session.candidates) { $candidate in
                            Toggle(isOn: $candidate.isSelected) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(
                                        "\(candidate.id + 1) · \(candidate.part.link == nil ? localized("text") : localized("link"))"
                                    )
                                    .font(.caption)
                                    Text(candidate.part.text)
                                        .lineLimit(4)
                                        .textSelection(.enabled)
                                }
                            }.toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(minHeight: 150)
                Picker(localized("Save results"), selection: $session.mode) {
                    ForEach(SplitSaveMode.allCases, id: \.rawValue) { Text($0.label).tag($0) }
                }
                if session.mode == .replace {
                    Text(
                        localized(
                            "The original will be removed. Unselected content is not included in the new cards. Undo restores the original."
                        )
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                if session.evictedCount > 0 {
                    let count = session.evictedCount
                    Toggle(localized("Allow removal of \(count) older history items"), isOn: $session.confirmEviction)
                }
            }
            if let error = session.error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button(localized("Cancel"), action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button(localized("Save")) { session.commit() }
                    .disabled(!session.canSave || (session.evictedCount > 0 && !session.confirmEviction))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(minWidth: 560, idealWidth: 640, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
        .textFieldStyle(.roundedBorder)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: session.mode) { _, _ in session.refreshAssessment() }
        .onChange(of: session.candidates.map(\.isSelected)) { _, _ in session.refreshAssessment() }
    }
}

struct SplitGroupView: View {
    @ObservedObject var session: SplitGroupSession
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Choose original or parts")).font(.title2)
            if let source = session.source {
                Toggle(localized("Complete original"), isOn: $session.original)
                if !source.pinnedMetadata.hidesContent {
                    Text(source.payload.transformableText ?? "").lineLimit(3).font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(source.splitGroup?.parts ?? []) { part in
                            Toggle(
                                isOn: Binding(
                                    get: { session.selected.contains(part.id) },
                                    set: { session.toggle(part.id, enabled: $0) })
                            ) {
                                HStack {
                                    Text(source.pinnedMetadata.hidesContent ? "••••••••" : part.text).lineLimit(4)
                                    if !source.pinnedMetadata.hidesContent, session.matches(part) {
                                        Image(systemName: "magnifyingglass").accessibilityLabel(
                                            localized("Search match"))
                                    }
                                }
                            }.toggleStyle(.checkbox)
                        }
                    }
                }
                Text(localized("Selected parts are combined in their original order with line breaks."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = session.error { Text(error).foregroundStyle(.red) }
            HStack {
                Button(localized("Cancel"), action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button(session.action == .paste ? localized("Paste") : localized("Copy")) { session.commit() }
                    .disabled(!session.valid || (!session.original && session.selected.isEmpty))
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 520, height: 500)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SplitGroupPreview: View {
    let source: ClipboardItem
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(localized("Complete original")).font(.headline)
                RichTextPreviewPane(item: source).frame(minHeight: 100, maxHeight: 180)
                ForEach(source.splitGroup?.parts ?? []) { part in
                    Divider()
                    RichTextPreviewPane(
                        item: ClipboardItem(
                            id: part.id, payload: part.payload, source: source.source,
                            copiedAt: source.copiedAt, isPinned: false, rtf: part.rtf)
                    )
                    .frame(minHeight: 80, maxHeight: 180)
                }
            }
        }
    }
}

struct SplitVersionView: View {
    @ObservedObject var store: HistoryViewStateStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Choose a format to split")).font(.title2)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    IndexedForEach(store.splitVersions) { index, item in
                        VStack(alignment: .leading) {
                            let number = index + 1
                            Text(localized("Format \(number)"))
                            RichTextPreviewPane(item: item).frame(height: 100)
                        }
                        .beButton { store.beginSplit(item.id) }
                    }
                }
            }
            Button(localized("Cancel")) { store.closeSplitSessions() }
        }.padding(20).frame(width: 460, height: 340).background(Color(nsColor: .windowBackgroundColor))
    }
}
