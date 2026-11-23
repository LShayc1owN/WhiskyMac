// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@available(macOS 26, *)
struct MacOS26HistoryHidingOptions: View {
    let includesTypes: Bool
    let confirm: (HistoryHidingRule) -> Void
    let cancel: () -> Void
    @State var draft: HistoryHidingDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                includesTypes ? localized("Hide by type or source") : localized("Choose hiding time"),
                systemImage: includesTypes ? "line.3.horizontal.decrease.circle" : "clock"
            )
            .font(.title3.weight(.semibold))
            if includesTypes {
                typeSelection
                Text(localized("Source to hide")).font(.headline)
                Toggle(isOn: $draft.includesHandoff) {
                    Label(localized("Handoff"), systemImage: "macbook.and.iphone")
                }
                .toggleStyle(.checkbox)
            }
            Text(localized("Hide cards before")).font(.headline)
            Picker(localized("Hide cards before"), selection: $draft.usesNow) {
                Text(localized("Now")).tag(true)
                Text(localized("Specific time")).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if !draft.usesNow {
                DatePicker(
                    localized("Date and time"), selection: $draft.date, in: ...Date(),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.field)
                .fixedSize(horizontal: false, vertical: true)
            }
            Text(localized("Newer cards stay visible. History is not deleted."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(localized("Cancel"), action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(localized("Confirm")) {
                    if let rule = draft.rule(includingTypes: includesTypes, now: Date()) { confirm(rule) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(includesTypes && draft.categories.isEmpty && !draft.includesHandoff)
            }
        }
        .padding(18)
        .frame(width: 360)
        .environment(\.locale, Locale(identifier: AppLocalization.language ?? Locale.current.identifier))
        .background(CardActionPopoverLayer())
    }

    private var typeSelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(localized("Types to hide")).font(.headline)
                Spacer()
                Button(draft.allTypesSelected ? localized("Deselect all") : localized("Select all types")) {
                    draft.toggleAllTypes()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("clipboard-hide-all-types")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ContentCategory.allCases, id: \.self) { category in
                        Toggle(isOn: selection(for: category)) {
                            Label(category.hidingTitle, systemImage: category.symbolName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .toggleStyle(.checkbox)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                }
                .padding(4)
            }
            .frame(height: 212)
            .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        }
    }

    private func selection(for category: ContentCategory) -> Binding<Bool> {
        Binding(
            get: { draft.categories.contains(category) },
            set: { selected in
                if selected { draft.categories.insert(category) } else { draft.categories.remove(category) }
            })
    }
}
