// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

@available(macOS 26, *)
struct MacOS26OnboardingIllustration: View {
    enum Scene { case welcome, tools, ready }
    let scene: Scene
    let menuSymbol: String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        LinearGradient(
                            colors: [
                                MacOS26OnboardingStyle.green.opacity(0.13),
                                MacOS26OnboardingStyle.orange.opacity(0.07),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().fill(MacOS26OnboardingStyle.green.opacity(0.06))
                    .frame(width: 230, height: 230).offset(x: 190, y: -75)
                Circle().strokeBorder(MacOS26OnboardingStyle.green.opacity(0.1), lineWidth: 1)
                    .frame(width: 290, height: 290).offset(x: -230, y: 120)
                illustration
                    .frame(width: 600, height: scene == .welcome ? 280 : 230)
                    .scaleEffect(min(geometry.size.width / 620, geometry.size.height / (scene == .welcome ? 300 : 250)))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            scene == .welcome
                ? localized("Illustration: the menu bar opens a searchable row of clipboard cards.")
                : scene == .tools
                    ? localized("Illustration: pin useful cards and arrange a paste stack.")
                    : localized("Illustration: your clipboard is ready, with the menu bar as your starting point."))
    }

    @ViewBuilder private var illustration: some View {
        switch scene {
        case .welcome: desktop
        case .tools: tools
        case .ready: ready
        }
    }

    private var desktop: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "apple.logo").font(.system(size: 12))
                Spacer()
                if let image = AppSymbol.image(named: menuSymbol, pointSize: 15) {
                    Image(nsImage: image).foregroundStyle(MacOS26OnboardingStyle.green)
                        .frame(width: 28, height: 23)
                        .background(MacOS26OnboardingStyle.green.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))
                }
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
                Text("09:41").font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .font(.system(size: 11))
            .padding(.horizontal, 20).padding(.vertical, 7)
            .background(MacOS26OnboardingStyle.card.opacity(0.85), in: Capsule())
            .padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(localized("Search your clipboard"))
                    Spacer()
                    Image(systemName: "line.3.horizontal.decrease")
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    pill(localized("All"), selected: true)
                    pill(localized("Text"))
                    pill(localized("Images"))
                    pill(localized("Links"))
                    Spacer()
                    Image(systemName: "pin").foregroundStyle(MacOS26OnboardingStyle.orange)
                }
                HStack(spacing: 10) {
                    sampleCard(
                        symbol: "text.alignleft", tint: MacOS26OnboardingStyle.green, title: localized("A good idea"),
                        lines: [104, 120, 80], selected: true)
                    sampleCard(
                        symbol: "photo", tint: MacOS26OnboardingStyle.orange, title: localized("A little inspiration"),
                        lines: [], selected: false)
                    sampleCard(symbol: "link", tint: .blue, title: "whiskymac", lines: [100, 65], selected: false)
                }
            }
            .padding(17)
            .background(MacOS26OnboardingStyle.card, in: RoundedRectangle(cornerRadius: 17))
            .shadow(color: MacOS26OnboardingStyle.green.opacity(0.12), radius: 15, y: 7)
            .padding(.horizontal, 30)
        }
    }

    private var tools: some View {
        HStack(spacing: 32) {
            ZStack(alignment: .topTrailing) {
                sampleCard(
                    symbol: "text.alignleft", tint: MacOS26OnboardingStyle.green,
                    title: localized("Your everyday snippet"), lines: [115, 92, 105], selected: true
                )
                .frame(width: 200, height: 133)
                .rotationEffect(.degrees(-5))
                Image(systemName: "pin.fill").font(.system(size: 21))
                    .foregroundStyle(MacOS26OnboardingStyle.orange)
                    .rotationEffect(.degrees(22)).offset(x: 4, y: -13)
            }
            Image(systemName: "arrow.right").font(.system(size: 23, weight: .light))
                .foregroundStyle(MacOS26OnboardingStyle.green)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(1...3, id: \.self) { index in
                    HStack(spacing: 13) {
                        Text("\(index)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(MacOS26OnboardingStyle.green)
                            .frame(width: 24, height: 24)
                            .background(MacOS26OnboardingStyle.green.opacity(0.1), in: Circle())
                        Capsule().fill(.primary.opacity(0.1)).frame(width: CGFloat(130 - index * 15), height: 5)
                        Spacer()
                    }
                    .padding(9).background(MacOS26OnboardingStyle.card, in: RoundedRectangle(cornerRadius: 10))
                }
            }.frame(width: 210)
        }
    }

    private var ready: some View {
        HStack(spacing: 36) {
            ZStack {
                Circle().strokeBorder(MacOS26OnboardingStyle.green.opacity(0.1)).frame(width: 165, height: 165)
                Circle().fill(MacOS26OnboardingStyle.card).frame(width: 126, height: 126)
                    .shadow(color: MacOS26OnboardingStyle.green.opacity(0.12), radius: 18, y: 8)
                MacOS26AppSymbolView(pointSize: 72).foregroundStyle(MacOS26OnboardingStyle.green)
                Image(systemName: "checkmark.circle.fill").font(.system(size: 32))
                    .foregroundStyle(MacOS26OnboardingStyle.green).background(MacOS26OnboardingStyle.card, in: Circle())
                    .offset(x: 44, y: 48)
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(["doc.on.doc", "magnifyingglass", "arrow.up.doc"], id: \.self) { symbol in
                    HStack(spacing: 15) {
                        Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(MacOS26OnboardingStyle.green)
                            .frame(width: 24)
                        Capsule().fill(MacOS26OnboardingStyle.green.opacity(0.16)).frame(width: 110, height: 6)
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                            .foregroundStyle(MacOS26OnboardingStyle.green)
                    }
                }
            }
        }
    }

    private func pill(_ text: String, selected: Bool = false) -> some View {
        Text(text).font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(selected ? MacOS26OnboardingStyle.green : .secondary)
            .background(selected ? MacOS26OnboardingStyle.green.opacity(0.12) : .primary.opacity(0.035), in: Capsule())
    }

    private func sampleCard(symbol: String, tint: Color, title: String, lines: [CGFloat], selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol).foregroundStyle(tint)
                Spacer()
                Circle().fill(tint.opacity(0.35)).frame(width: 5, height: 5)
            }.font(.system(size: 12))
            Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            if lines.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.1))
                    Image(systemName: "mountain.2.fill").font(.system(size: 31)).foregroundStyle(tint.opacity(0.5))
                }.frame(height: 37)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    IndexedForEach(lines, indexID: \.self) { _, width in
                        Capsule().fill(.primary.opacity(0.09)).frame(width: width, height: 4)
                    }
                }.frame(height: 37, alignment: .top)
            }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            selected ? tint.opacity(0.16) : MacOS26OnboardingStyle.paper, in: RoundedRectangle(cornerRadius: 12)
        )
    }
}

@available(macOS 26, *)
struct MacOS26OnboardingPrivacyDiagram: View {
    @Environment(\.interfaceTypography) private var typography

    var body: some View {
        Group {
            if typography.usesLargeLayout {
                VStack(alignment: .leading, spacing: 18) { lanes }
            } else {
                HStack(alignment: .top, spacing: 14) { lanes }
            }
        }
        .padding(18)
        .background(MacOS26OnboardingStyle.green.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var lanes: some View {
        lane("internaldrive", localized("Regular apps"), localized("Local history"), .teal)
        lane("timer", localized("Sensitive apps"), localized("Temporary session"), .orange)
        lane("nosign", localized("Excluded apps"), localized("Never recorded"), .secondary)
    }

    private func lane(_ symbol: String, _ title: String, _ destination: String, _ tint: Color) -> some View {
        let icon = Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(tint)
            .frame(height: 29).accessibilityHidden(true)
        let title = Text(title).font(typography.font(size: 11, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
        let destination = Text(destination).font(typography.font(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

        return Group {
            if typography.usesLargeLayout {
                HStack(alignment: .top, spacing: 10) {
                    icon.frame(width: 27)
                    VStack(alignment: .leading, spacing: 4) {
                        title
                        destination
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 9) {
                    icon
                    title
                    Image(systemName: "arrow.down").foregroundStyle(tint.opacity(0.5)).accessibilityHidden(true)
                    destination
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
