// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct HistoryHidingOptions: View {
    let includesTypes: Bool
    let confirm: (HistoryHidingRule) -> Void
    let cancel: () -> Void
    @State var draft = HistoryHidingDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                includesTypes ? localized("Hide by type or source") : localized("Choose hiding time"),
                systemImage: includesTypes ? "line.3.horizontal.decrease.circle" : "clock"
            )
            .font(.title3.weight(.semibold))
            if includesTypes {
                HStack {
                    Text(localized("Types to hide")).font(.headline)
                    Spacer()
                    Button(draft.allTypesSelected ? localized("Deselect all") : localized("Select all types")) {
                        draft.toggleAllTypes()
                    }
                    .buttonStyle(.borderless)
                }
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(ContentCategory.allCases, id: \.rawValue) { category in
                            typeRow(category)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 212)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
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
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(localized("Cancel"), action: cancel).keyboardShortcut(.cancelAction)
                Button(localized("Confirm")) {
                    if let rule = draft.rule(includingTypes: includesTypes, now: Date()) { confirm(rule) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(includesTypes && draft.categories.isEmpty && !draft.includesHandoff)
            }
        }
        .padding(18)
        .frame(width: 360)
        .environment(\.locale, Locale(identifier: AppLocalization.language ?? Locale.current.identifier))
        .background(CardActionPopoverLayer())
    }

    private func typeRow(_ category: ContentCategory) -> some View {
        let selected = draft.categories.contains(category)
        return Button {
            if selected { draft.categories.remove(category) } else { draft.categories.insert(category) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.matcha : .secondary)
                Image(systemName: category.symbolName).foregroundStyle(.secondary).frame(width: 20)
                Text(category.hidingTitle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(selected ? Color.matcha.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.hidingTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? localized("Selected") : "")
    }

}

extension ContentCategory {
    var hidingTitle: String {
        switch self {
        case .text: localized("text").capitalized
        case .code: localized("code").capitalized
        case .color: localized("color").capitalized
        case .link: localized("link").capitalized
        case .path: localized("path").capitalized
        case .image: localized("image").capitalized
        case .files: localized("files").capitalized
        }
    }
}
