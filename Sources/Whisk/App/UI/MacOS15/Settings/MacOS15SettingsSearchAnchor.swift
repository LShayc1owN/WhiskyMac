// WhiskyMac: modified or added 2026-11-07 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

private struct MacOS15SettingsSearchHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var macOS15SettingsSearchHighlight: String? {
        get { self[MacOS15SettingsSearchHighlightKey.self] }
        set { self[MacOS15SettingsSearchHighlightKey.self] = newValue }
    }
}

extension ContainerValues {
    @Entry var macOS15SettingsSearchAnchorID: String? = nil
}

private struct MacOS15SettingsSearchLayoutKey: PreferenceKey {
    static let space = "settingsDetailContent"
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct MacOS15SettingsSearchScrollRequest: Equatable {
    let offset: CGFloat
    let revision: Int
}

/// Scroll to the measured row, including controls embedded in a grouped section.
struct MacOS15SettingsSearchScrollView<Content: View>: View {
    @ObservedObject var search: SettingsSearchModel
    let section: SettingsSectionID
    @ViewBuilder var content: Content
    @State private var anchors: [String: CGRect] = [:]
    @State private var viewportHeight: CGFloat = 0
    @State private var position = ScrollPosition(edge: .top)
    @State private var scrolledRevision: Int?
    @SettingsAccessibility private var accessibility

    private var request: MacOS15SettingsSearchScrollRequest? {
        guard search.destination?.section == section, let id = search.highlightedAnchor,
            let row = anchors[id], row.height > 0, viewportHeight > 0
        else { return nil }
        let inset = max(0, (viewportHeight - row.height) / 2)
        return MacOS15SettingsSearchScrollRequest(offset: max(0, row.minY - inset), revision: search.navigationRevision)
    }

    var body: some View {
        ScrollView {
            content
                .frame(minHeight: section == .licenses ? viewportHeight : nil, alignment: .top)
                .coordinateSpace(name: MacOS15SettingsSearchLayoutKey.space)
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.containerSize.height
        } action: { _, height in
            viewportHeight = height
        }
        .onPreferenceChange(MacOS15SettingsSearchLayoutKey.self) { anchors = $0 }
        .onChange(of: request, initial: true) { _, request in
            guard let request, scrolledRevision != request.revision else { return }
            scrolledRevision = request.revision
            withAnimation(accessibility.reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                position.scrollTo(y: request.offset)
            }
        }
    }
}

extension View {
    func macOS15SettingsSearchAnchor(_ id: String) -> some View {
        modifier(MacOS15SettingsSearchAnchor(id: id))
    }
}

private struct MacOS15SettingsSearchAnchor: ViewModifier {
    let id: String
    @Environment(\.macOS15SettingsSearchHighlight) private var highlight
    @SettingsAccessibility private var accessibility

    func body(content: Content) -> some View {
        content
            .id(id)
            .containerValue(\.macOS15SettingsSearchAnchorID, id)
            .background {
                if highlight == id {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: MacOS15SettingsSearchLayoutKey.self,
                            value: [id: geometry.frame(in: .named(MacOS15SettingsSearchLayoutKey.space))])
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.tint, lineWidth: 2)
                    .opacity(highlight == id ? 0.85 : 0)
                    .padding(-4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .animation(accessibility.reduceMotion ? nil : .easeOut(duration: 0.2), value: highlight == id)
    }
}
