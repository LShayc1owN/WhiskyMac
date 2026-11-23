// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26SettingsBrand: View {
    enum Placement { case sidebar, toolbar }

    @ObservedObject var appearance: AppearanceSettingsStore
    var buildInfo = AppBuildInfo.current
    let placement: Placement
    @State private var symbolRevision = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            if placement == .sidebar { symbol }
            VStack(alignment: placement == .sidebar ? .leading : .trailing, spacing: 1) {
                Text(verbatim: AppIdentity.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(Color(white: scheme == .dark ? 0.92 : 0.10))
                HStack(spacing: 7) {
                    Text(verbatim: buildInfo.version ?? "—")
                        .foregroundStyle(Color(white: scheme == .dark ? 0.71 : 0.34))
                        .monospacedDigit()
                    if placement == .sidebar { Spacer(minLength: 0) }
                    Text(verbatim: buildInfo.channel.rawValue)
                        .fontWeight(.medium)
                        .foregroundStyle(channelColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(channelColor.opacity(0.14), in: Capsule())
                }
                .font(.system(size: 10))
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
        Button {
            if !reduceMotion { symbolRevision += 1 }
        } label: {
            if let image = AppSymbol.image(named: AppSymbol.brandName, pointSize: 32) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .font(.system(size: 26))
                    .foregroundStyle(Color.readableAccent(in: scheme, color: appearance.nsAccent))
                    .symbolEffect(.bounce, value: symbolRevision)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppIdentity.displayName)
    }

    private var channelColor: Color {
        let color: NSColor =
            switch buildInfo.channel {
            case .debug: .systemRed
            case .release: .systemGreen
            case .beta: .systemBlue
            }
        return .readableAccent(in: scheme, color: color)
    }
}
