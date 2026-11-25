// WhiskyMac: modified or added 2026-11-08 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct MacOS15SettingsNavigationControl: View {
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

struct MacOS15SettingsBrandView: View {
    private var typography: InterfaceTypography { appearance.interfaceTypography }

    enum Placement { case sidebar, toolbar }
    @ObservedObject var appearance: AppearanceSettingsStore
    var buildInfo = AppBuildInfo.current
    var placement: Placement = .sidebar
    @State private var symbolEvent = MacOS15SettingsSymbolEvent()
    @SettingsAccessibility private var accessibility
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder
    var body: some View {
        if placement == .toolbar && typography.usesLargeLayout {
            symbol
                .help([AppIdentity.displayName, buildInfo.versionWithChannel].compactMap { $0 }.joined(separator: " "))
                .accessibilityValue(buildInfo.versionWithChannel ?? buildInfo.channel.rawValue)
        } else {
            brand
        }
    }

    private var brand: some View {
        let layout =
            placement == .sidebar && typography.usesLargeLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if placement == .sidebar { symbol }
            VStack(alignment: placement == .toolbar ? .trailing : .leading, spacing: 2) {
                Text(AppIdentity.displayName)
                    .font(typography.font(size: 18, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                MacOS15VersionLabel(
                    version: buildInfo.versionNumber ?? "—", buildInfo: buildInfo,
                    typography: typography, spreads: placement == .sidebar)
            }
            .frame(maxWidth: placement == .sidebar ? .infinity : nil, alignment: .leading)
            if placement == .toolbar { symbol }
        }
        .fixedSize(horizontal: placement == .toolbar, vertical: true)
        .padding(placement == .toolbar ? 2 : 8)
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowOpened)) { _ in
            play(.bounce, speed: 1, reversed: false)
        }
    }

    private var symbol: some View {
        MacOS15SettingsAnimatedSymbol(
            symbolName: AppSymbol.brandName, event: symbolEvent,
            color: appearance.nsAccent.macOS15ReadableAccent(in: scheme), reduceMotion: accessibility.reduceMotion,
            pointSize: 32
        )
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .beButton {
            play(
                MacOS15SettingsSymbolEffect.allCases.randomElement() ?? .bounce,
                speed: Double.random(in: 0.75...1.4), reversed: Bool.random())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppIdentity.displayName)
    }

    private func play(_ effect: MacOS15SettingsSymbolEffect, speed: Double, reversed: Bool) {
        symbolEvent = MacOS15SettingsSymbolEvent(
            revision: symbolEvent.revision + 1, effect: effect, speed: speed, reversed: reversed)
    }
}

struct MacOS15VersionLabel: View {
    let version: String
    let buildInfo: AppBuildInfo
    let typography: InterfaceTypography
    var spreads = false
    @Environment(\.colorScheme) private var scheme
    @SettingsAccessibility private var accessibility

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                versionText.fixedSize()
                if spreads { Spacer(minLength: 0) }
                channelBadge.fixedSize()
            }
            VStack(alignment: .leading, spacing: 3) {
                versionText
                channelBadge
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var versionText: some View {
        Text(verbatim: version)
            .font(typography.font(size: 10).monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var channelBadge: some View {
        let color: NSColor =
            switch buildInfo.channel {
            case .debug: .systemRed
            case .beta: .systemYellow
            case .release: .systemGreen
            }
        return Text(verbatim: buildInfo.channelLabel)
            .font(typography.font(.caption).weight(.medium))
            .foregroundStyle(Color.macOS15ReadableAccent(in: scheme, color: color))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: color).opacity(accessibility.increasedContrast ? 0.26 : 0.14), in: Capsule())
    }
}
