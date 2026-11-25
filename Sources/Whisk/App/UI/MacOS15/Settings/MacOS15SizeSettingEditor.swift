// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct MacOS15SizeSettingEditor<Preview: View>: View {
    @Environment(\.interfaceTypography) private var typography

    let title: String
    let savedValue: Double
    let defaultValue: Double
    let range: ClosedRange<Double>
    var usesPercentage = false
    @Binding var draft: SizeSettingDraft
    let save: (Double) -> Void
    let previewOnScreen: () -> Void
    @ViewBuilder let preview: () -> Preview

    private var size: Binding<Double> {
        Binding(get: { draft.value(saved: savedValue) }, set: { draft.proposedValue = $0 })
    }

    private var value: Double { size.wrappedValue }

    private var sizeLayout: AnyLayout {
        typography.usesLargeLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            sizeLayout {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                if !typography.usesLargeLayout { Spacer(minLength: 12) }
                HStack(spacing: 10) {
                    Slider(value: size, in: range)
                        .frame(minWidth: 100, maxWidth: 220)
                        .accessibilityLabel(title)
                    if usesPercentage {
                        Text(
                            value.formatted(
                                .percent.locale(AppLocalization.interfaceLocale).precision(.fractionLength(0)))
                        )
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 64, alignment: .trailing)
                    } else {
                        let input = CardSizeInput()
                        HStack(spacing: 6) {
                            MacOS15NumericField(title: title, value: size, format: input.format, parse: input.parse)
                                .accessibilityIdentifier("card-size-input")
                            Text(localized("pt")).foregroundStyle(.secondary)
                        }
                        .fixedSize()
                    }
                }
            }
            if draft.hasChanges(saved: savedValue) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { editingButtons }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) { editingButtons }
                }
            } else if value != defaultValue {
                restoreDefaultButton
            }

            Divider()
                .opacity(0.4)

            Text(localized("Preview"))
                .font(typography.font(.caption))
                .foregroundStyle(.secondary)

            preview()

            Button(localized("Preview on screen"), systemImage: "macwindow") {
                previewOnScreen()
            }
            .macOS15SettingsAction()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var editingButtons: some View {
        editButton(localized("Restore last saved size"), symbol: "arrow.uturn.backward") {
            draft.revert()
        }
        .buttonStyle(.bordered)
        editButton(localized("Save current setting"), symbol: "checkmark") {
            draft.save(using: save)
        }
        .buttonStyle(.borderedProminent)
        if value != defaultValue { restoreDefaultButton }
    }

    private var restoreDefaultButton: some View {
        editButton(localized("Restore default size"), symbol: "arrow.counterclockwise") {
            draft.proposedValue = defaultValue
        }
        .buttonStyle(.bordered)
    }

    private func editButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                Text(verbatim: title)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol).imageScale(.small)
            }
            .labelStyle(.titleAndIcon)
            .padding(.vertical, typography.points(2))
        }
    }
}

struct MacOS15FilterTagSizePreview: View {
    @Environment(\.interfaceTypography) private var typography
    let scale: Double

    private var filters: FilterBarViewState {
        func chip(_ id: String, _ title: String, _ icon: String, active: Bool = false) -> FilterChip {
            FilterChip(
                id: id, label: title, sourceBundleID: nil, icon: .symbol(icon), accessibilityLabel: title,
                isActive: active, isFocused: false)
        }
        return FilterBarViewState(
            all: [chip("preview-all", localized("All"), "square.grid.2x2", active: true)], apps: [],
            kinds: [
                chip("preview-text", localized("Text"), "text.alignleft"),
                chip("preview-image", localized("Image"), "photo"),
            ])
    }

    var body: some View {
        MacOS15FilterBarView(
            filters: filters, tagScale: scale, hoverEnabled: false,
            onToggleApp: { _ in }, onToggleKind: { _ in }, onFocusApp: { _ in }, onFocusKind: { _ in }
        )
        .frame(height: MacOS15FilterTagMetrics(scale: scale, typography: typography).totalRowHeight)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Tag size"))
        .accessibilityValue("\(Int((scale * 100).rounded()))%")
    }
}
