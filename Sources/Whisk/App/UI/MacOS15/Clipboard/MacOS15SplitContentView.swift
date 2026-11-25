// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct MacOS15AuxiliaryDialog<Content: View, Footer: View>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }

            Divider()
            footer
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MacOS15DialogActionStyle: ButtonStyle {
    @Environment(\.interfaceTypography) private var typography
    @Environment(\.isEnabled) private var isEnabled

    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(typography.font(.body).weight(prominent ? .semibold : .regular))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                let shape = RoundedRectangle(cornerRadius: 7)
                shape.fill(.fill.secondary)
                    .overlay {
                        if prominent, isEnabled { shape.fill(Color.accentColor.opacity(0.16)) }
                    }
                    .overlay {
                        if configuration.isPressed { shape.fill(.primary.opacity(0.12)) }
                    }
            }
            .foregroundStyle(isEnabled ? .primary : .secondary)
    }
}

struct MacOS15DialogActions<Primary: View>: View {
    let close: () -> Void
    @ViewBuilder let primary: Primary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                cancel.fixedSize()
                Spacer(minLength: 8)
                primary.fixedSize()
            }

            VStack(alignment: .trailing, spacing: 6) {
                cancel
                primary
            }
        }
    }

    private var cancel: some View {
        Button(localized("Cancel"), action: close)
            .buttonStyle(MacOS15DialogActionStyle())
            .keyboardShortcut(.cancelAction)
    }
}

struct MacOS15SplitContentView: View {
    @Environment(\.interfaceTypography) private var typography

    @ObservedObject var session: SplitSession
    let close: () -> Void

    var body: some View {
        MacOS15AuxiliaryDialog {
            Text(localized("Split options"))
                .font(typography.font(.headline))
                .accessibilityAddTraits(.isHeader)
            if session.source != nil {
                splitOptions
                Divider()
                results
                Divider()
                saveOptions
            }
            if let error = session.error {
                Text(error)
                    .foregroundStyle(.red)
                    .font(typography.font(.caption))
            }
        } footer: {
            MacOS15DialogActions(close: close) {
                Button(localized("Save")) { session.commit() }
                    .buttonStyle(MacOS15DialogActionStyle(prominent: true))
                    .disabled(!session.canSave || (session.evictedCount > 0 && !session.confirmEviction))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: session.mode) { _, _ in session.refreshAssessment() }
        .onChange(of: session.candidates.map(\.isSelected)) { _, _ in session.refreshAssessment() }
    }

    @ViewBuilder private var splitOptions: some View {
        optionMenu(localized("Split rule"), selection: $session.options.rule, options: SplitRule.allCases) { $0.label }
        if session.options.rule == .delimiters {
            ViewThatFits(in: .horizontal) {
                HStack { delimiters }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { delimiters }
            }
            let title = localized("Custom separator (literal text)")
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(title, text: $session.options.customDelimiter, prompt: Text(verbatim: ""))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.background, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
            }
        }
        if session.options.rule == .links {
            Toggle(isOn: $session.options.linksOnly) {
                Text(localized("Only links (off: split text and links)"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Toggle(isOn: $session.options.keepDelimiter) {
                Text(localized("Keep separators at the end of the previous part"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Toggle(isOn: $session.options.trimWhitespace) {
            Text(localized("Trim surrounding whitespace"))
                .fixedSize(horizontal: false, vertical: true)
        }
        Toggle(isOn: $session.options.plainText) {
            Text(localized("Plain text (discard formatting)"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var delimiters: some View {
        ForEach(SplitDelimiter.allCases, id: \.rawValue) { delimiter in
            Toggle(
                isOn: Binding(
                    get: { session.options.delimiters.contains(delimiter) },
                    set: { enabled in
                        if enabled {
                            session.options.delimiters.insert(delimiter)
                        } else {
                            session.options.delimiters.remove(delimiter)
                        }
                    })
            ) {
                Text(delimiter.label).fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder private var results: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(localized("Results"))
                .font(typography.font(.title3))
                .accessibilityAddTraits(.isHeader)
            Text("\(session.candidates.filter(\.isSelected).count) / \(session.candidates.count)")
                .font(typography.font(.caption))
                .monospacedDigit()
            if session.analyzing {
                ProgressView().controlSize(.small)
            }
        }
        if !session.analyzing, session.candidates.isEmpty {
            Text(localized("No split results. Try another rule."))
                .foregroundStyle(.secondary)
        }
        ForEach($session.candidates) { $candidate in
            Toggle(isOn: $candidate.isSelected) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        "\(candidate.id + 1) · \(candidate.part.link == nil ? localized("text") : localized("link"))"
                    )
                    .font(typography.font(.caption))
                    Text(candidate.part.text)
                        .font(typography.plainText.font(.body))
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder private var saveOptions: some View {
        optionMenu(localized("Save results"), selection: $session.mode, options: SplitSaveMode.allCases) { $0.label }
        if session.mode == .replace {
            Text(
                localized(
                    "The original will be removed. Unselected content is not included in the new cards. Undo restores the original."
                )
            )
            .font(typography.font(.caption)).foregroundStyle(.secondary)
        }
        if session.evictedCount > 0 {
            let count = session.evictedCount
            Toggle(isOn: $session.confirmEviction) {
                Text(localized("Allow removal of \(count) older history items"))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func optionMenu<Option: Hashable>(
        _ title: String, selection: Binding<Option>, options: [Option], label: (Option) -> String
    ) -> some View {
        let selected = label(selection.wrappedValue)
        let values = options.map { ($0, label($0)) }
        let menu = Menu {
            Picker(title, selection: selection) {
                ForEach(values, id: \.0) { option, name in
                    Text(name).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(selected)
                .font(typography.font(.callout))
                .fixedSize(horizontal: false, vertical: true)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel(title)
        .accessibilityValue(selected)

        let heading = Text(title).fixedSize(horizontal: false, vertical: true).accessibilityHidden(true)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                heading.fixedSize()
                menu.fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                heading
                menu
            }
        }
    }
}

struct MacOS15SplitGroupView: View {
    @Environment(\.interfaceTypography) private var typography

    @ObservedObject var session: SplitGroupSession
    let close: () -> Void

    var body: some View {
        MacOS15AuxiliaryDialog {
            Text(localized("Choose original or parts"))
                .font(typography.font(.headline))
                .accessibilityAddTraits(.isHeader)
            if let source = session.source {
                Toggle(isOn: $session.original) {
                    Text(localized("Complete original")).fixedSize(horizontal: false, vertical: true)
                }
                if !session.hidesContent {
                    Text(source.payload.transformableText ?? "")
                        .lineLimit(3)
                        .font(typography.plainText.font(.caption))
                        .foregroundStyle(.secondary)
                }
                Text(localized("Selected parts are combined in their original order with line breaks."))
                    .font(typography.font(.caption)).foregroundStyle(.secondary)
                ForEach(source.splitGroup?.parts ?? []) { part in
                    Toggle(
                        isOn: Binding(
                            get: { session.selected.contains(part.id) },
                            set: { session.toggle(part.id, enabled: $0) })
                    ) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(session.hidesContent ? "••••••••" : part.text)
                                .font(typography.plainText.font(.body)).lineLimit(4)
                            if !session.hidesContent, session.matches(part) {
                                Image(systemName: "magnifyingglass")
                                    .font(typography.font(.caption))
                                    .accessibilityLabel(localized("Search match"))
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            if let error = session.error {
                Text(error).foregroundStyle(.red)
            }
        } footer: {
            MacOS15DialogActions(close: close) {
                Button(session.action == .paste ? localized("Paste") : localized("Copy")) { session.commit() }
                    .buttonStyle(MacOS15DialogActionStyle(prominent: true))
                    .disabled(!session.valid || (!session.original && session.selected.isEmpty))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

struct MacOS15SplitGroupPreview: View {
    @Environment(\.interfaceTypography) private var typography

    let source: ClipboardItem
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(localized("Complete original")).font(typography.font(.headline))
                MacOS15RichTextPreviewPane(item: source).frame(minHeight: 100, maxHeight: 180)
                ForEach(source.splitGroup?.parts ?? []) { part in
                    Divider()
                    MacOS15RichTextPreviewPane(content: part.richText, fallback: part.payload.searchableText ?? "")
                        .frame(minHeight: 80, maxHeight: 180)
                }
            }
        }
    }
}

struct MacOS15SplitVersionView: View {
    @Environment(\.interfaceTypography) private var typography

    @ObservedObject var store: HistoryViewStateStore

    var body: some View {
        MacOS15AuxiliaryDialog {
            Text(localized("Choose a format to split"))
                .font(typography.font(.headline))
                .accessibilityAddTraits(.isHeader)
            IndexedForEach(store.splitVersions) { index, item in
                let number = index + 1
                let title = localized("Format \(number)")
                Button {
                    store.beginSplit(item.id)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(typography.font(.headline))
                            .fixedSize(horizontal: false, vertical: true)
                        MacOS15RichTextPreviewPane(item: item)
                            .frame(maxWidth: .infinity)
                            .frame(height: 100)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
            }
        } footer: {
            Button(localized("Cancel")) { store.closeSplitSessions() }
                .buttonStyle(MacOS15DialogActionStyle())
                .keyboardShortcut(.cancelAction)
        }
    }
}
