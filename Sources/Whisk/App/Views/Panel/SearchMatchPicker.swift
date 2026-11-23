import AppKit
import SwiftUI

struct SearchMatchPicker: View {
    let mode: SearchMatchMode
    let select: (SearchMatchMode) -> Void

    var body: some View {
        if #available(macOS 26, *) {
            MacOS26SearchMatchPicker(mode: mode, select: select)
        } else {
            legacyMenu
        }
    }

    private var legacyMenu: some View {
        Menu {
            Picker(localized("Search match mode"), selection: Binding(get: { mode }, set: select)) {
                ForEach(SearchMatchMode.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(mode.title)
                .font(.system(size: NSFont.smallSystemFontSize))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .controlSize(.small)
        .fixedSize()
        .accessibilityLabel(localized("Search match mode"))
        .accessibilityValue(mode.title)
        .accessibilityIdentifier("clipboard-search-match-mode")
        .help(localized("Search match mode"))
    }
}

extension SearchMatchMode {
    var title: String {
        switch self {
        case .fuzzy: localized("Fuzzy Match")
        case .containing: localized("Containing")
        case .matchingWord: localized("Matching Word")
        case .startingWith: localized("Starting With")
        case .endingWith: localized("Ending With")
        }
    }
}
