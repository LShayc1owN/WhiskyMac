// WhiskyMac: modified or added 2026-11-08 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct SettingsNavigationControl: View {
    @ObservedObject var appearance: AppearanceSettingsStore

    private var title: String {
        appearance.navigation == .top ? localized("Use sidebar navigation") : localized("Use top navigation")
    }

    var body: some View {
        Image(systemName: appearance.navigation == .top ? "sidebar.left" : "rectangle.topthird.inset.filled")
            .font(.system(size: 14))
            .frame(width: 40, height: 28)
            .contentShape(Rectangle())
            .beButton {
                appearance.navigation = appearance.navigation == .top ? .sidebar : .top
            }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityLabel(title)
            .frame(width: 40, height: 28)
    }
}

struct SettingsBrandView: View {
    enum Placement { case sidebar, toolbar }
    @ObservedObject var appearance: AppearanceSettingsStore
    var buildInfo = AppBuildInfo.current
    var placement: Placement = .sidebar
    @State private var symbolEvent = SettingsSymbolEvent()
    @SettingsAccessibility private var accessibility
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            if placement == .sidebar { symbol }
            VStack(alignment: placement == .toolbar ? .trailing : .leading, spacing: 2) {
                Text(AppIdentity.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if placement == .toolbar { Spacer(minLength: 0) }
                    Text(verbatim: buildInfo.version ?? "—")
                        .lineLimit(nil)
                        .multilineTextAlignment(placement == .toolbar ? .trailing : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if placement == .sidebar { Spacer() }
                    Text(verbatim: buildInfo.channel.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(channelTextColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(channelColor.opacity(0.14), in: Capsule())
                        .fixedSize()
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: placement == .toolbar ? .trailing : .leading)
                .accessibilityElement(children: .combine)
            }
            .frame(maxWidth: .infinity, alignment: placement == .toolbar ? .trailing : .leading)
            if placement == .toolbar { symbol }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowOpened)) { _ in
            play(.bounce, speed: 1, reversed: false)
        }
    }

    private var symbol: some View {
        SettingsAnimatedSymbol(
            symbolName: AppSymbol.brandName, event: symbolEvent,
            color: appearance.nsAccent.readableAccent(in: scheme), reduceMotion: accessibility.reduceMotion,
            pointSize: 32
        )
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .beButton {
            play(
                SettingsSymbolEffect.allCases.randomElement() ?? .bounce,
                speed: Double.random(in: 0.75...1.4), reversed: Bool.random())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppIdentity.displayName)
    }

    private var channelColor: Color {
        switch buildInfo.channel {
        case .debug: .red
        case .release: .green
        case .beta: .blue
        }
    }

    private var channelTextColor: Color {
        guard scheme == .light else { return channelColor }
        let color: NSColor
        switch buildInfo.channel {
        case .debug: color = .systemRed
        case .release: color = .systemGreen
        case .beta: color = .systemBlue
        }
        return .readableAccent(in: scheme, color: color)
    }

    private func play(_ effect: SettingsSymbolEffect, speed: Double, reversed: Bool) {
        symbolEvent = SettingsSymbolEvent(
            revision: symbolEvent.revision + 1, effect: effect, speed: speed, reversed: reversed)
    }
}
