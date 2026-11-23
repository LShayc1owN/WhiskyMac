// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@available(macOS 26, *)
struct MacOS26SearchMatchPicker: View {
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
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
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

@available(macOS 26, *)
struct MacOS26ClipboardSearchSurface: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background(
                Color(white: scheme == .dark ? 0.19 : 1).opacity(reduceTransparency ? 1 : 0.36),
                in: .capsule
            )
            .overlay {
                Capsule().strokeBorder(.primary.opacity(0.12)).allowsHitTesting(false)
            }
            .glassEffect(reduceTransparency ? .identity : .regular, in: .capsule)
    }
}
