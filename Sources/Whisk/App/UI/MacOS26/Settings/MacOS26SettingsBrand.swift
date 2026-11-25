// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26SettingsBrand: View {
    private var typography: InterfaceTypography { appearance.interfaceTypography }

    enum Placement { case sidebar, toolbar }

    @ObservedObject var appearance: AppearanceSettingsStore
    var buildInfo = AppBuildInfo.current
    let placement: Placement
    @State private var symbolRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            VStack(alignment: placement == .sidebar ? .leading : .trailing, spacing: 1) {
                Text(verbatim: AppIdentity.displayName)
                    .font(typography.font(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(Color(white: scheme == .dark ? 0.92 : 0.10))
                MacOS26VersionLabel(
                    version: buildInfo.versionNumber ?? "—", buildInfo: buildInfo,
                    typography: typography, spreads: placement == .sidebar)
            }
            .accessibilityElement(children: .combine)
            if placement == .toolbar { symbol }
        }
        .fixedSize(horizontal: placement == .toolbar, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowOpened)) { _ in
            if !reduceMotion { symbolRevision += 1 }
        }
    }

    private var symbol: some View {
        Group {
            if let image = AppSymbol.image(named: AppSymbol.brandName, pointSize: 32) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .font(.system(size: 26))
                    .foregroundStyle(Color.macOS26ReadableAccent(in: scheme, color: appearance.nsAccent))
                    .symbolEffect(.bounce, value: symbolRevision)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .beButton { if !reduceMotion { symbolRevision += 1 } }
        .buttonStyle(.plain)
        .accessibilityLabel(AppIdentity.displayName)
    }

}

@available(macOS 26, *)
struct MacOS26VersionLabel: View {
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
            .foregroundStyle(Color.macOS26ReadableAccent(in: scheme, color: color))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(nsColor: color).opacity(accessibility.increasedContrast ? 0.26 : 0.14), in: Capsule())
    }
}
