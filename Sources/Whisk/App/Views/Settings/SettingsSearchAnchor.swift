// WhiskyMac: modified or added 2026-11-07 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

private struct SettingsSearchHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingsSearchHighlight: String? {
        get { self[SettingsSearchHighlightKey.self] }
        set { self[SettingsSearchHighlightKey.self] = newValue }
    }
}

extension ContainerValues {
    @Entry var settingsSearchAnchorID: String? = nil
}

private struct SettingsSearchLayoutKey: PreferenceKey {
    static let defaultValue: Set<String> = []
    static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) { value.formUnion(nextValue()) }
}

private struct SettingsSearchScrollRequest: Equatable {
    let anchor: String
    let revision: Int
}

/// Wait for the actual target to be laid out, including after switching subpages.
struct SettingsSearchScrollView<Content: View>: View {
    @ObservedObject var search: SettingsSearchModel
    let section: SettingsSectionID
    @ViewBuilder var content: Content
    @State private var laidOutAnchors: Set<String> = []
    @State private var scrolledRevision: Int?
    @SettingsAccessibility private var accessibility

    private var request: SettingsSearchScrollRequest? {
        guard search.destination?.section == section,
            let anchor = search.destination?.anchor, laidOutAnchors.contains(anchor)
        else { return nil }
        return SettingsSearchScrollRequest(anchor: anchor, revision: search.navigationRevision)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }
                .onPreferenceChange(SettingsSearchLayoutKey.self) { anchors in
                    laidOutAnchors = anchors
                }
                .task(id: request) {
                    guard let request, scrolledRevision != request.revision else { return }
                    // The geometry preference arrives during layout. Register the
                    // target with ScrollViewReader before making a scroll request.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    scrolledRevision = request.revision
                    withAnimation(accessibility.reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        proxy.scrollTo(request.anchor, anchor: .center)
                    }
                }
        }
    }

}

extension View {
    func settingsSearchAnchor(_ id: String) -> some View {
        modifier(SettingsSearchAnchor(id: id))
    }
}

private struct SettingsSearchAnchor: ViewModifier {
    let id: String
    @Environment(\.settingsSearchHighlight) private var highlight
    @SettingsAccessibility private var accessibility

    func body(content: Content) -> some View {
        content
            .id(id)
            .containerValue(\.settingsSearchAnchorID, id)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: SettingsSearchLayoutKey.self,
                        value: geometry.size.width > 0 && geometry.size.height > 0 ? [id] : [])
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
