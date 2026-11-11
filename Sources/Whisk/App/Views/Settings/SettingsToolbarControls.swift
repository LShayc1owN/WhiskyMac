// WhiskyMac: modified or added 2026-11-08 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct SettingsNavigationControl: View {
    @ObservedObject var appearance: AppearanceSettingsStore

    private var title: String {
        appearance.navigation == .top ? localized("Use sidebar navigation") : localized("Use top navigation")
    }

    var body: some View {
        Image(systemName: appearance.navigation == .top ? "sidebar.left" : "rectangle.topthird.inset.filled")
            .font(.system(size: 14))
            .frame(width: 20, height: 18)
            .beButton {
                appearance.navigation = appearance.navigation == .top ? .sidebar : .top
            }
            .buttonStyle(SettingsGlassButtonStyle())
            .help(title)
            .accessibilityLabel(title)
            .frame(width: 40, height: 28)
    }
}

struct SettingsToolbarBrand: View {
    @ObservedObject var appearance: AppearanceSettingsStore
    @State private var symbolEvent = SettingsSymbolEvent()
    @SettingsAccessibility private var accessibility

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(AppIdentity.displayName)
                    .font(.system(size: 20, weight: .semibold))
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            SettingsAnimatedSymbol(
                symbolName: appearance.defaultStatusSymbol, event: symbolEvent,
                color: appearance.nsAccent, reduceMotion: accessibility.reduceMotion, pointSize: 36
            )
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .beButton {
                play(
                    SettingsSymbolEffect.allCases.randomElement() ?? .bounce,
                    speed: Double.random(in: 0.75...1.4), reversed: Bool.random())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppIdentity.displayName)
        }
        .fixedSize()
        .padding(8)
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowOpened)) { _ in
            play(.bounce, speed: 1, reversed: false)
        }
    }

    private func play(_ effect: SettingsSymbolEffect, speed: Double, reversed: Bool) {
        symbolEvent = SettingsSymbolEvent(
            revision: symbolEvent.revision + 1, effect: effect, speed: speed, reversed: reversed)
    }
}
