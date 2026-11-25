// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

@available(macOS 26, *)
struct MacOS26SettingsForm<Header: View, Content: View>: View {
    @ObservedObject var search: SettingsSearchModel
    let section: SettingsSectionID
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @State private var renderedAnchors: Set<String> = []

    private struct ScrollRequest: Equatable {
        let anchor: String
        let revision: Int
    }

    private var request: ScrollRequest? {
        guard search.destination?.section == section, let anchor = search.destination?.anchor,
            renderedAnchors.contains(anchor)
        else { return nil }
        return ScrollRequest(anchor: anchor, revision: search.navigationRevision)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: 18) {
                        Group(sections: content) { sections in
                            ForEach(sections) { section in
                                MacOS26SettingsGroup(section: section)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .toggleStyle(MacOS26SettingsSwitchStyle())
            .environment(\.macOS26SettingsSearchHighlight, search.highlightedAnchor)
            .onPreferenceChange(MacOS26SettingsLaidOutAnchors.self) { renderedAnchors = $0 }
            .task(id: request) {
                guard let request else { return }
                // Wait for the destination row to register after a section change.
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(request.anchor, anchor: .center)
            }
        }
    }
}

@available(macOS 26, *)
private struct MacOS26SettingsSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 16) {
            configuration.label.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .accessibilityElement(children: .combine)
    }
}

@available(macOS 26, *)
private struct MacOS26SettingsGroup: View {
    @Environment(\.interfaceTypography) private var typography

    let section: SectionConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(section.header) { header in
                header.font(typography.font(.headline)).padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 0) {
                ForEach(section.content) { row in
                    VStack(spacing: 0) {
                        row
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        if row.id != section.content.last?.id {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                    .id(row.containerValues.macOS26SettingsAnchorID ?? "settings-row-\(row.id)")
                }
            }
            .background(.fill.tertiary, in: MacOS26SettingsSurface.rounded(minimum: 22))
            .containerShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            ForEach(section.footer) { footer in
                footer
                    .font(typography.font(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@available(macOS 26, *)
extension ContainerValues {
    @Entry fileprivate var macOS26SettingsAnchorID: String? = nil
}

@available(macOS 26, *)
private struct MacOS26SettingsLaidOutAnchors: PreferenceKey {
    static let defaultValue: Set<String> = []

    static func reduce(value: inout Set<String>, nextValue: () -> Set<String>) {
        value.formUnion(nextValue())
    }
}

@available(macOS 26, *)
private struct MacOS26SettingsSearchHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

@available(macOS 26, *)
extension EnvironmentValues {
    var macOS26SettingsSearchHighlight: String? {
        get { self[MacOS26SettingsSearchHighlightKey.self] }
        set { self[MacOS26SettingsSearchHighlightKey.self] = newValue }
    }
}

@available(macOS 26, *)
extension View {
    func macOS26SettingsSearchAnchor(_ id: String) -> some View {
        modifier(MacOS26SettingsSearchAnchor(id: id))
    }
}

@available(macOS 26, *)
private struct MacOS26SettingsSearchAnchor: ViewModifier {
    let id: String
    @Environment(\.macOS26SettingsSearchHighlight) private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .containerValue(\.macOS26SettingsAnchorID, id)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: MacOS26SettingsLaidOutAnchors.self,
                        value: geometry.size.width > 0 && geometry.size.height > 0 ? [id] : [])
                }
            }
            .overlay {
                MacOS26SettingsSurface.rounded(minimum: 10)
                    .stroke(.tint, lineWidth: 2)
                    .padding(-3)
                    .opacity(highlight == id ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: highlight == id)
            .accessibilityIdentifier(id)
            .id(id)
    }
}
