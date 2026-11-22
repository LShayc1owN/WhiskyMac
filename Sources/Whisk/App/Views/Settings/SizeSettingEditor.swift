// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct SizeSettingEditor<Preview: View>: View {
    let title: String
    let symbol: String
    let savedValue: Double
    let defaultValue: Double
    let range: ClosedRange<Double>
    var usesPercentage = false
    @Binding var draft: SizeSettingDraft
    let save: (Double) -> Void
    let previewOnScreen: () -> Void
    @ViewBuilder let preview: () -> Preview

    private var value: Double {
        draft.value(saved: savedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                SettingsRowLabel(title, symbol: symbol, tint: .indigo)
                Spacer(minLength: 12)
                Slider(value: Binding(get: { value }, set: { draft.proposedValue = $0 }), in: range)
                    .frame(minWidth: 100, maxWidth: 220)
                    .accessibilityLabel(title)
                Text(usesPercentage ? "\(Int((value * 100).rounded()))%" : "\(Int(value.rounded())) \(localized("pt"))")
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
            if draft.hasChanges(saved: savedValue) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { editingButtons }
                    VStack(alignment: .leading, spacing: 10) { editingButtons }
                }
            } else if value != defaultValue {
                restoreDefaultButton
            }

            Divider()
                .opacity(0.4)

            Text(localized("Preview"))
                .font(.caption)
                .foregroundStyle(.secondary)

            preview()

            Button(localized("Preview on screen"), systemImage: "macwindow") {
                previewOnScreen()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var editingButtons: some View {
        Button(localized("Restore last saved size")) {
            draft.revert()
        }
        Button(localized("Save current setting")) {
            draft.save(using: save)
        }
        .buttonStyle(.borderedProminent)
        if value != defaultValue {
            restoreDefaultButton
        }
    }

    private var restoreDefaultButton: some View {
        Button(localized("Restore default size")) {
            draft.proposedValue = defaultValue
        }
    }
}

struct FilterTagSizePreview: View {
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
        FilterBarView(
            filters: filters, tagScale: scale, hoverEnabled: false,
            onToggleApp: { _ in }, onToggleKind: { _ in }, onFocusApp: { _ in }, onFocusKind: { _ in }
        )
        .frame(height: FilterTagMetrics(scale: scale).totalRowHeight)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Tag size"))
        .accessibilityValue("\(Int((scale * 100).rounded()))%")
    }
}
