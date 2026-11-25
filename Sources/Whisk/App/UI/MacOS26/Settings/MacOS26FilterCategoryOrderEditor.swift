// WhiskyMac: added 2026-11-25 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

@available(macOS 26, *)
struct MacOS26FilterCategoryOrderEditor: View {
    @Environment(\.interfaceTypography) private var typography

    @Environment(\.colorScheme) private var settingsScheme
    @ObservedObject var settings: GeneralSettingsStore
    var previewScheme: ColorScheme? = nil

    private var order: FilterCategoryOrder { settings.filterCategoryOrder }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Preview"))
                .font(typography.font(.caption))
                .foregroundStyle(.secondary)
            preview
            Divider()
            VStack(spacing: 4) {
                IndexedForEach(order.categories, id: \.self) { index, category in
                    row(category, at: index)
                }
            }
            Button(localized("Restore default order"), systemImage: "arrow.counterclockwise") {
                settings.setFilterCategoryOrder(.standard)
            }
            .macOS26SettingsAction()
            .disabled(order == .standard)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preview: some View {
        let filters = HistoryPresenter().filterBar(
            from: FilterContext(chips: order.categories.map(ChipEntry.category)))
        return MacOS26FilterBarView(
            horizontalMargin: 0, filters: filters, tagScale: settings.filterTagScale, hoverEnabled: false,
            onToggleApp: { _ in }, onToggleKind: { _ in }, onFocusApp: { _ in }, onFocusKind: { _ in }
        )
        .frame(height: MacOS26FilterTagMetrics(scale: settings.filterTagScale, typography: typography).totalRowHeight)
        .disabled(true)
        .environment(\.colorScheme, previewScheme ?? settingsScheme)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("Preview"))
        .accessibilityValue(filters.kinds.map(\.label).joined(separator: ", "))
    }

    private func row(_ category: ContentCategory, at index: Int) -> some View {
        let name = category.hidingTitle
        return HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Label(name, systemImage: category.symbolName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .draggable(FilterCategoryDrag(category))
            .help(localized("Drag to reorder"))
            Button(String(format: localized("Move %@ up"), name), systemImage: "chevron.up") {
                move(category, toIndex: index - 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(index == 0)
            Button(String(format: localized("Move %@ down"), name), systemImage: "chevron.down") {
                move(category, toIndex: index + 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(index == order.categories.count - 1)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .dropDestination(for: FilterCategoryDrag.self) { items, _ in
            guard items.count == 1, let source = items.first?.category, source != category else { return false }
            settings.setFilterCategoryOrder(order.moving(source, to: category))
            return true
        }
    }

    private func move(_ category: ContentCategory, toIndex index: Int) {
        guard order.categories.indices.contains(index) else { return }
        settings.setFilterCategoryOrder(order.moving(category, to: order.categories[index]))
    }
}
