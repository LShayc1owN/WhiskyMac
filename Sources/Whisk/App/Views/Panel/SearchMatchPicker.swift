import AppKit
import SwiftUI

struct SearchMatchPicker: View {
    private static let titleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

    let mode: SearchMatchMode
    let select: (SearchMatchMode) -> Void

    var body: some View {
        Menu {
            Picker(localized("Search match mode"), selection: Binding(get: { mode }, set: select)) {
                ForEach(SearchMatchMode.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Text(mode.title)
                .font(.system(size: Self.titleFont.pointSize))
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

private extension SearchMatchMode {
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
