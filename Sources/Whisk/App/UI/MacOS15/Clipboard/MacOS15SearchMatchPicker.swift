import AppKit
import SwiftUI

struct MacOS15SearchMatchPicker: View {
    @Environment(\.interfaceTypography) private var typography

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
            HStack(spacing: 4) {
                if typography.usesLargeLayout {
                    Image(systemName: "line.3.horizontal.decrease")
                } else {
                    Text(mode.title)
                    Image(systemName: "chevron.down")
                        .font(typography.font(size: 9, weight: .medium))
                }
            }
            .font(typography.font(.callout))
            .foregroundStyle(.secondary)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(localized("Search match mode"))
        .accessibilityValue(mode.title)
        .accessibilityIdentifier("clipboard-search-match-mode")
        .help(localized("Search match mode"))
    }
}
