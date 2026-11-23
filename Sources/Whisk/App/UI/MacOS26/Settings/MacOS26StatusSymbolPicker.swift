// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26StatusSymbolPickerRow: View {
    let title: String
    @Binding var selection: String
    let defaultName: String
    @State private var choosing = false

    var body: some View {
        HStack {
            Text(title).fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: 12)
            Button {
                choosing = true
            } label: {
                HStack(spacing: 8) {
                    if let image = AppSymbol.image(named: selection) {
                        Image(nsImage: image).renderingMode(.template)
                    }
                    Text(selection).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 260, alignment: .trailing)
            }
            .accessibilityLabel(title)
            .accessibilityValue(selection)
            .sheet(isPresented: $choosing) {
                MacOS26StatusSymbolPicker(title: title, selection: $selection, defaultName: defaultName)
            }
        }
    }
}

@available(macOS 26, *)
private struct MacOS26StatusSymbolPicker: View {
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(localized("Restore Defaults")) { choose(defaultName) }
                    .buttonStyle(.glass)
                Button(localized("Done")) { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 14) {
                Group {
                    if let image = AppSymbol.image(named: selection, pointSize: 28) {
                        Image(nsImage: image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(.tint)
                            .symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: previewRevision)
                    }
                }
                .frame(width: 44, height: 44)
                Text(selection)
                    .font(.headline)
                    .textSelection(.enabled)
            }
            TextField(localized("Search SF Symbols by name"), text: $query)
                .textFieldStyle(.roundedBorder)
            if loading { ProgressView().controlSize(.small) }
            symbols
        }
        .padding(24)
        .frame(width: 720, height: 560)
        .onExitCommand { dismiss() }
        .task {
            let loaded = await Task.detached(priority: .userInitiated) { SymbolCatalog.availableNames }.value
            guard !Task.isCancelled else { return }
            names = loaded
            loading = false
        }
    }

    private var symbols: some View {
        let matches = matches
        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(matches, id: \.self) { name in
                    Button {
                        choose(name)
                    } label: {
                        VStack(spacing: 7) {
                            if let image = AppSymbol.image(named: name, pointSize: 22) {
                                Image(nsImage: image).renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 30)
                            }
                            Text(name)
                                .font(.caption2)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .padding(4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 74)
                        .contentShape(Rectangle())
                        .background {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selection == name ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.04))
                        }
                    }
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
        .defaultScrollAnchor(.top)
        .frame(maxHeight: .infinity)
    }

    private func choose(_ name: String) {
        selection = name
        if !reduceMotion { previewRevision += 1 }
    }
}
