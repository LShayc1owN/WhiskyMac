// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26StatusSymbolPickerRow: View {
    @Environment(\.interfaceTypography) private var typography

    let title: String
    @Binding var selection: String
    let defaultName: String
    @State private var choosing = false

    var body: some View {
        let layout =
            typography.usesLargeLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            if !typography.usesLargeLayout { Spacer(minLength: 0) }
            HStack(spacing: 8) {
                if let image = AppSymbol.image(named: selection, pointSize: typography.points(15)) {
                    Image(nsImage: image).renderingMode(.template)
                }
                Text(verbatim: selection)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(typography.font(.caption))
                    .foregroundStyle(.secondary)
            }
            .beButton { choosing = true }
            .accessibilityLabel(title)
            .accessibilityValue(selection)
            .sheet(isPresented: $choosing) {
                MacOS26StatusSymbolPicker(title: title, selection: $selection, defaultName: defaultName)
            }
        }
    }
}

@available(macOS 26, *)
struct MacOS26StatusSymbolPicker: View {
    @Environment(\.interfaceTypography) private var typography

    let title: String
    @Binding var selection: String
    let defaultName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var names = AppSymbol.customNames
    @State private var loading = true
    @State private var previewRevision = 0

    private var matches: [String] {
        var result = SymbolCatalog.matching(names, query: query)
        let exact = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !exact.isEmpty, !result.contains(exact), AppSymbol.sourceImage(named: exact) != nil {
            result.insert(exact, at: 0)
        }
        return result
    }

    var body: some View {
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 800, height: 640)
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(typography.font(.title3).weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            let prompt = localized("Search SF Symbols by name")
            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text(prompt)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextField(prompt, text: $query, prompt: Text(verbatim: ""))
                    .textFieldStyle(.plain)
            }
            .font(typography.font(.body))
            .padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary).allowsHitTesting(false))
            symbols
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack { buttons }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .trailing) { buttons }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .layoutPriority(1)
        }
        .padding(16)
        .frame(width: min(720, visible.width - 32), height: min(560, visible.height - 48))
        .background(.background)
        .onExitCommand { dismiss() }
        .task {
            let loaded = await Task.detached(priority: .userInitiated) { SymbolCatalog.availableNames }.value
            guard !Task.isCancelled else { return }
            names = loaded
            loading = false
        }
    }

    @ViewBuilder private var buttons: some View {
        Button {
            choose(defaultName)
        } label: {
            Label(localized("Restore Defaults"), systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(MacOS26DialogActionStyle())
        Button(localized("Done")) { dismiss() }
            .buttonStyle(MacOS26DialogActionStyle(prominent: true))
            .keyboardShortcut(.cancelAction)
    }

    private var symbols: some View {
        let matches = matches
        return ScrollView {
            HStack(spacing: 12) {
                if let image = AppSymbol.image(named: selection, pointSize: typography.points(28)) {
                    Image(nsImage: image).renderingMode(.template)
                        .resizable().scaledToFit().frame(width: typography.room(36), height: typography.room(36))
                        .symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: previewRevision)
                        .accessibilityHidden(true)
                }
                Text(verbatim: selection)
                    .font(typography.font(.headline))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if loading { ProgressView().controlSize(.small) }
            }
            .padding(.bottom, 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: typography.room(84)), spacing: 8)], spacing: 8) {
                ForEach(matches, id: \.self) { name in
                    VStack(spacing: 7) {
                        if let image = AppSymbol.image(named: name, pointSize: typography.points(22)) {
                            Image(nsImage: image).renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: typography.room(32), height: typography.room(30))
                        }
                        Text(verbatim: name)
                            .font(typography.font(.caption2))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.center)
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 74)
                    .contentShape(Rectangle())
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selection == name ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                    }
                    .beButton { choose(name) }
                    .buttonStyle(.plain)
                    .help(name)
                    .accessibilityLabel(name)
                    .accessibilityAddTraits(selection == name ? .isSelected : [])
                }
            }
            if matches.isEmpty && !loading {
                Text(localized("No matching symbols"))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func choose(_ name: String) {
        selection = name
        if !reduceMotion { previewRevision += 1 }
    }
}
