import AppKit
import SwiftUI

struct StatusSymbolPickerRow: View {
    let title: String
    @Binding var selection: String
    let defaultName: String
    @State private var choosing = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 8) {
                if let image = AppSymbol.image(named: selection) {
                    Image(nsImage: image).renderingMode(.template)
                }
                Text(selection).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .frame(maxWidth: 260, alignment: .trailing)
            .beButton { choosing = true }
            .accessibilityLabel(title)
            .accessibilityValue(selection)
            .sheet(isPresented: $choosing) {
                StatusSymbolPicker(title: title, selection: $selection, defaultName: defaultName)
            }
        }
    }
}

struct StatusSymbolPicker: View {
    let title: String
    @Binding var selection: String
    let defaultName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var names = AppSymbol.customNames
    @State private var loading = true
    @State private var animationTrigger = 0

    private var matches: [String] {
        var result = SymbolCatalog.matching(names, query: query)
        // Accept exact names added by a newer OS, even before the bundled index is updated.
        let exact = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !exact.isEmpty, !result.contains(exact), AppSymbol.sourceImage(named: exact) != nil {
            result.insert(exact, at: 0)
        }
        return result
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                Button(localized("Restore Defaults")) { choose(defaultName) }
                Button(localized("Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 14) {
                if let image = AppSymbol.image(named: selection, pointSize: 28) {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                        .symbolEffect(.wiggle.byLayer, options: .nonRepeating, value: animationTrigger)
                        .frame(width: 44, height: 44)
                }
                Text(selection).font(.headline).textSelection(.enabled)
                Spacer()
            }
            TextField(localized("Search SF Symbols by name"), text: $query)
                .textFieldStyle(.roundedBorder)
            if loading { ProgressView().controlSize(.small) }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                    ForEach(matches, id: \.self) { name in
                        VStack(spacing: 6) {
                            if let image = AppSymbol.image(named: name, pointSize: 22) {
                                Image(nsImage: image)
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 32, height: 30)
                            }
                            Text(name).font(.system(size: 10)).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity).frame(height: 74)
                        .background(
                            selection == name ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                        .overlay {
                            if selection == name {
                                RoundedRectangle(cornerRadius: 9).stroke(Color.accentColor, lineWidth: 2)
                            }
                        }
                        .contentShape(Rectangle())
                        .beButton { choose(name) }
                        .buttonStyle(.plain)
                        .help(name)
                        .accessibilityLabel(name)
                        .accessibilityAddTraits(selection == name ? .isSelected : [])
                    }
                }
                if matches.isEmpty && !loading { Text(localized("No matching symbols")).foregroundStyle(.secondary) }
            }
        }
        .padding(24)
        .frame(width: 720, height: 560)
        .background(.background)
        .task {
            let loaded = await Task.detached(priority: .userInitiated) { SymbolCatalog.availableNames }.value
            guard !Task.isCancelled else { return }
            names = loaded
            loading = false
        }
    }

    private func choose(_ name: String) {
        selection = name
        if !reduceMotion { animationTrigger += 1 }
    }
}
