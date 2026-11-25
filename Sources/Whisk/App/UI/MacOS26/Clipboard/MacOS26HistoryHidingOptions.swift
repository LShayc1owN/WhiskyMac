// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@available(macOS 26, *)
struct MacOS26HistoryHidingOptions: View {
    @Environment(\.interfaceTypography) private var typography

    let includesTypes: Bool
    let confirm: (HistoryHidingRule) -> Void
    let cancel: () -> Void
    @State var draft: HistoryHidingDraft

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
        .background(MacOS26CardActionPopoverLayer())
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                includesTypes ? localized("Hide by type or source") : localized("Choose hiding time"),
                systemImage: includesTypes ? "line.3.horizontal.decrease.circle" : "clock"
            )
            .font(typography.font(.title3).weight(.semibold))
            if includesTypes {
                typeSelection
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
                MacOS26MenuRow(
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
                .font(typography.font(.caption))
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var timeOptions: some View {
        Text(localized("Now")).tag(true)
        Text(localized("Specific time")).tag(false)
    }

    private var dateField: some View {
        MacOS26HidingDateField(date: $draft.date, typography: typography)
            .fixedSize()
    }

    private var typeSelection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(localized("Types to hide")).font(typography.font(.headline))
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

@available(macOS 26, *)
private struct MacOS26HidingDateField: NSViewRepresentable {
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
