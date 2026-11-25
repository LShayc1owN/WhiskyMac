// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct MacOS15HistoryHidingOptions: View {
    @Environment(\.interfaceTypography) private var typography

    let includesTypes: Bool
    let confirm: (HistoryHidingRule) -> Void
    let cancel: () -> Void
    @State var draft = HistoryHidingDraft()

    var body: some View {
        Group {
            if typography.usesLargeLayout {
                ScrollView { form }
                    .frame(maxHeight: max(240, (NSScreen.main?.visibleFrame.height ?? 720) - 100))
            } else {
                form
            }
        }
        .frame(width: min(typography.room(360), (NSScreen.main?.visibleFrame.width ?? 680) - 32))
        .environment(\.locale, AppLocalization.language.map { Locale(identifier: $0) } ?? .current)
        .background(MacOS15CardActionPopoverLayer())
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                includesTypes ? localized("Hide by type or source") : localized("Choose hiding time"),
                systemImage: includesTypes ? "line.3.horizontal.decrease.circle" : "clock"
            )
            .font(typography.font(.title3).weight(.semibold))
            if includesTypes {
                HStack {
                    Text(localized("Types to hide")).font(typography.font(.headline))
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
                Text(localized("Source to hide")).font(typography.font(.headline))
                Toggle(isOn: $draft.includesHandoff) {
                    Label(localized("Handoff"), systemImage: "macbook.and.iphone")
                }
                .toggleStyle(.checkbox)
            }
            if typography.isStandard {
                Text(localized("Hide cards before")).font(typography.font(.headline))
                Picker(localized("Hide cards before"), selection: $draft.usesNow) {
                    timeOptions
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } else {
                MacOS15SettingsPicker(
                    localized("Hide cards before"), selection: $draft.usesNow,
                    display: { $0 ? localized("Now") : localized("Specific time") }
                ) { timeOptions }
            }
            if !draft.usesNow {
                if typography.isStandard {
                    DatePicker(
                        localized("Date and time"), selection: $draft.date, in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.field)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Text(localized("Date and time"))
                            dateField
                        }.fixedSize()
                        VStack(alignment: .leading, spacing: 6) {
                            Text(localized("Date and time"))
                            dateField
                        }
                    }
                }
            }
            Text(localized("Newer cards stay visible. History is not deleted."))
                .font(typography.font(.caption)).foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var timeOptions: some View {
        Text(localized("Now")).tag(true)
        Text(localized("Specific time")).tag(false)
    }

    private var dateField: some View {
        MacOS15HidingDateField(date: $draft.date, typography: typography)
            .fixedSize()
    }

    private func typeRow(_ category: ContentCategory) -> some View {
        let selected = draft.categories.contains(category)
        return HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.square.fill" : "square")
                .foregroundStyle(selected ? Color.macOS15Matcha : .secondary)
            Image(systemName: category.symbolName).foregroundStyle(.secondary).frame(width: typography.room(20))
            Text(category.hidingTitle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Color.macOS15Matcha.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .beButton { if selected { draft.categories.remove(category) } else { draft.categories.insert(category) } }
        .buttonStyle(.plain)
        .accessibilityLabel(category.hidingTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityValue(selected ? localized("Selected") : "")
    }

}

private struct MacOS15HidingDateField: NSViewRepresentable {
    @Binding var date: Date
    let typography: InterfaceTypography

    func makeCoordinator() -> HistoryHidingDateControl { HistoryHidingDateControl(date: $date) }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.addSubview(context.coordinator.picker)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.update(date: $date, locale: context.environment.locale, typography: typography)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        context.coordinator.picker.frame.size
    }
}
