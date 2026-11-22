// WhiskyMac: modified or added 2026-11-05 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct AboutSettingsView: View {
    let section: SettingsSectionID
    var distribution: Distribution = .current
    @ObservedObject var updateChecker = UpdateChecker()
    @ObservedObject var general = GeneralSettingsStore()
    @ObservedObject var search = SettingsSearchModel()
    @ObservedObject var developerMode = DeveloperModeStore()

    private let projectURL = URL(string: "https://github.com/LShayc1owN/WhiskyMac")!
    private let developerURL = URL(string: "https://github.com/LShayc1owN")!
    private let upstreamURL = URL(string: "https://github.com/nathan-poncet/whisk")!
    private let issuesURL = URL(string: "https://github.com/LShayc1owN/WhiskyMac/issues/new")!
    private let donationURL = URL(string: "https://buymeacoffee.com/funclinkrev")!
    private static let feedbackAddress = "connect.whiskymac@outlook.com"
    private static let appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    @SettingsAccessibility private var accessibility

    private var developerHomepages: [ProfileHomepage] {
        [
            ProfileHomepage(title: localized("Lin Shay on GitHub"), destination: developerURL),
            ProfileHomepage(title: "Buy Me a Coffee", destination: donationURL),
        ]
    }

    var body: some View {
        SettingsSearchScrollView(search: search, section: section) {
            VStack(alignment: .leading, spacing: 18) {
                if section == .aboutApp {
                    aboutApp
                } else {
                    aboutDeveloper
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .id(section)
    }

    private var aboutApp: some View {
        VStack(alignment: .leading, spacing: 18) {
            versionCard
            group(localized("Source repositories")) {
                githubLink(localized("WhiskyMac on GitHub"), destination: projectURL)
                githubLink(localized("Original Whisk on GitHub"), destination: upstreamURL)
            }
            .settingsSearchAnchor("repositories")
            group(localized("Dependencies and credits")) {
                Text(dependencyCredits)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .settingsSearchAnchor("dependencies")
            group(localized("Translation contributors")) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    ForEach(AppLanguage.allCases.filter { $0 != .system }) { language in
                        GridRow(alignment: .firstTextBaseline) {
                            Text(language.label)
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    inlineWebsiteLink("ChatGPT", destination: URL(string: "https://chatgpt.com/")!)
                                    Text(verbatim: "By")
                                    inlineWebsiteLink("OpenAI", destination: URL(string: "https://openai.com/")!)
                                }
                                if language == .simplifiedChinese {
                                    HoverProfileLink(name: "LinShay 琳曦", homepages: developerHomepages)
                                }
                            }
                        }
                    }
                }
            }
            .settingsSearchAnchor("translations")
            group(localized("Feedback")) {
                githubLink(localized("Report a bug on GitHub"), destination: issuesURL)
                ExternalHomepageLink(
                    title: Self.feedbackAddress,
                    destination: URL(string: "mailto:\(Self.feedbackAddress)")!)
            }
            .settingsSearchAnchor("feedback")
            if developerMode.canChange {
                group(nil) {
                    Button(
                        developerMode.showsTools
                            ? localized("Disable Developer Mode") : localized("Enable Developer Mode")
                    ) {
                        developerMode.toggle()
                    }
                }
            }
        }
    }

    private var versionCard: some View {
        let shape = RoundedRectangle(cornerRadius: SettingsSurface.groupCornerRadius)
        return VStack(spacing: 0) {
            appIdentity
            if distribution.checksForUpdates {
                Divider()
                softwareUpdate
            }
        }
        .clipShape(shape)
        .settingsSurface(in: shape)
        .overlay {
            shape.strokeBorder(.primary.opacity(accessibility.increasedContrast ? 0.30 : 0.10))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var appIdentity: some View {
        HStack(spacing: 16) {
            Group {
                if let icon = Self.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    AppSymbolView(pointSize: 38)
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(AppIdentity.displayName)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    versionBadge
                }
                Text(appSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .settingsSearchAnchor("version")
        .padding(16)
        .background {
            Rectangle().fill(.tint.opacity(0.07))
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing))
        }
    }

    @ViewBuilder
    private var versionBadge: some View {
        let build = AppBuildInfo.current
        if let version = build.versionWithChannel {
            let color: Color =
                switch build.channel {
                case .debug: .red
                case .release: .green
                case .beta: .yellow
                }
            Text(verbatim: "\(localized("Version")) \(version)")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(accessibility.increasedContrast ? 0.40 : 0.26), in: Capsule())
                .fixedSize()
        }
    }

    private var appSummary: AttributedString {
        let project = "[WhiskyMac\u{00A0}↗](\(projectURL.absoluteString))"
        let upstream = "[Whisk\u{00A0}↗](\(upstreamURL.absoluteString))"
        let summary = localized("\(project) is a clipboard history app based on \(upstream).")
        return (try? AttributedString(markdown: summary)) ?? AttributedString(summary)
    }

    private var softwareUpdate: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                updateStatusIcon
                    .frame(width: 32, height: 32)
                    .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localized("Software Update"))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(updateStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let release = updateChecker.availableRelease {
                        Link(destination: release.page) {
                            Label(localized("Download update on GitHub"), systemImage: "arrow.up.right")
                                .font(.callout.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                checkForUpdatesButton
            }
            .settingsSearchAnchor("checkUpdates")
            .padding(.vertical, 14)

            Divider()

            Picker(
                localized("Update channel"),
                selection: Binding(get: { updateChecker.channel }, set: updateChecker.setChannel)
            ) {
                ForEach(UpdateChannel.allCases, id: \.self) { channel in
                    Text(channel.selectionTitle).tag(channel)
                }
            }
            .pickerStyle(.menu)
            .padding(.vertical, 10)
            .settingsSearchAnchor("updateChannel")

            Divider()

            Toggle(localized("Check for updates at launch"), isOn: $general.checkForUpdates)
                .toggleStyle(SettingsToggleStyle())
                .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
    }

    private var checkForUpdatesButton: some View {
        let disabled = !updateChecker.canCheckForUpdates || updateChecker.state == .checking
        return Button {
            updateChecker.checkNow()
        } label: {
            Label(localized("Check for updates"), systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .fixedSize()
    }

    @ViewBuilder
    private var updateStatusIcon: some View {
        switch updateChecker.state {
        case .idle:
            Image(systemName: "arrow.down.to.line").foregroundStyle(.tint)
        case .checking:
            ProgressView().controlSize(.small)
        case .noEligibleRelease, .awaitingStable:
            Image(systemName: "info.circle").foregroundStyle(.secondary)
        case .upToDate:
            Image(systemName: "checkmark").foregroundStyle(.green)
        case .available:
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.tint)
        case .failed:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    /// Keep the translated sentence's word order and let native text wrap its links.
    private var dependencyCredits: AttributedString {
        var text = AttributedString(
            localized("Based on Whisk. Includes Kenney UI Audio, SFX Kit and the Neovim icon."))
        let destinations: [(String, URL)] = [
            ("Whisk", upstreamURL),
            ("Kenney UI Audio", URL(string: "https://kenney.nl/assets/ui-audio")!),
            ("SFX Kit", URL(string: "https://github.com/wyzowl/sfx-kit")!),
            ("Neovim", URL(string: "https://store.neovim.io/products/neovim-sticker-logo-only")!),
        ]
        for (name, url) in destinations {
            guard let range = text.range(of: name) else { continue }
            var link = AttributedString(name)
            link.link = url
            var arrow = AttributedString(" ↗")
            arrow.link = url
            arrow.font = .caption2.weight(.semibold)
            link.append(arrow)
            text.replaceSubrange(range, with: link)
        }
        return text
    }

    private var updateStatus: String {
        switch updateChecker.state {
        case .idle:
            return updateChecker.canCheckForUpdates
                ? localized("Updates are downloaded from GitHub.")
                : localized("Update checks are unavailable in this build.")
        case .checking: return localized("Checking for updates…")
        case .upToDate: return localized("You’re up to date.")
        case .noEligibleRelease: return localized("No releases are available in this update channel.")
        case .awaitingStable:
            return localized("Your Beta is newer than the latest Release. Waiting for a newer Release.")
        case .available(let release): return String(format: localized("Update available: %@"), release.version)
        case .failed: return localized("Could not check for updates. Try again or visit GitHub.")
        }
    }

    private var aboutDeveloper: some View {
        VStack(alignment: .leading, spacing: 18) {
            group(nil) {
                HoverProfileLink(name: "Lin Shay", homepages: developerHomepages)
                    .font(.headline)
                Text(
                    localized(
                        "LinShay (琳曦) independently maintains WhiskyMac, with a focus on a more comfortable clipboard experience on macOS."
                    ))
            }
            .settingsSearchAnchor("developer")
            group(localized("Support development")) {
                ExternalHomepageLink(title: "Buy Me a Coffee", destination: donationURL)
            }
        }
    }

    private func githubLink(_ title: String, destination: URL) -> some View {
        ExternalHomepageLink(title: title, destination: destination)
    }

    private func inlineWebsiteLink(_ title: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack(spacing: 3) {
                Text(verbatim: title)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private func group<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.headline) }
            VStack(alignment: .leading, spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .settingsSurface(
                    in: RoundedRectangle(cornerRadius: SettingsSurface.groupCornerRadius, style: .continuous))
        }
        .buttonStyle(.bordered)
    }
}
