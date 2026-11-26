// WhiskyMac: modified or added 2026-11-05 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct MacOS15AboutSettingsView: View {
    @Environment(\.interfaceTypography) private var typography

    let section: SettingsSectionID
    var distribution: Distribution = .current
    var buildInfo = AppBuildInfo.current
    @ObservedObject var updateChecker = UpdateChecker()
    @ObservedObject var general = GeneralSettingsStore()
    @ObservedObject var developerMode = DeveloperModeStore()

    private let projectURL = URL(string: "https://github.com/LShayc1owN/WhiskyMac")!
    private let upstreamURL = URL(string: "https://github.com/nathan-poncet/whisk")!
    private let issuesURL = URL(string: "https://github.com/LShayc1owN/WhiskyMac/issues/new")!
    private static let feedbackAddress = "connect.whiskymac@outlook.com"
    private static let appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap { NSImage(contentsOf: $0) }

    @SettingsAccessibility private var accessibility

    var body: some View {
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

    private var aboutApp: some View {
        VStack(alignment: .leading, spacing: 18) {
            versionCard
            actionGroup(localized("Source repositories")) {
                githubLink(localized("WhiskyMac on GitHub"), destination: projectURL)
                githubLink(localized("Original Whisk on GitHub"), destination: upstreamURL)
            }
            .macOS15SettingsSearchAnchor("repositories")
            actionGroup(localized("Dependencies and credits")) {
                Text(upstreamCredit)
                    .fixedSize(horizontal: false, vertical: true)
                repositoryCredit(
                    "Kenney UI Audio", repository: "Calinou/kenney-ui-audio",
                    purpose: localized("provides click and switch sounds for clipboard copy feedback."))
                repositoryCredit(
                    "SFX Kit", repository: "wyzowl/sfx-kit",
                    purpose: localized("adds soft clicks, taps, snaps, and bubbles to the copy sound options."))
                repositoryCredit(
                    "Neovim", repository: "neovim/neovim",
                    purpose: localized("is the source of the code category icon in the original Whisk."))
            }
            .macOS15SettingsSearchAnchor("dependencies")
            group(localized("Translation contributors")) {
                translationCredits
            }
            .macOS15SettingsSearchAnchor("translations")
            actionGroup(localized("Feedback")) {
                githubLink(localized("Report a bug on GitHub"), destination: issuesURL)
                MacOS15ExternalHomepageLink(
                    title: Self.feedbackAddress,
                    destination: URL(string: "mailto:\(Self.feedbackAddress)")!)
            }
            .macOS15SettingsSearchAnchor("feedback")
            if developerMode.canChange {
                actionGroup(nil) {
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

    private var translationCredits: some View {
        let groups = TranslationCredits.byLanguage
        return ViewThatFits(in: .horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                ForEach(groups) { group in
                    GridRow(alignment: .firstTextBaseline) {
                        Text(group.language.label).accessibilityAddTraits(.isHeader)
                        contributors(in: group)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.language.label).accessibilityAddTraits(.isHeader)
                        contributors(in: group)
                    }
                }
            }
        }
    }

    private func contributors(in group: TranslationCredits.LanguageGroup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(group.products) { credit in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    creditIcon(TranslationCredits.aiProductSymbol, label: localized("AI assistance"))
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        inlineWebsiteLink(credit.product)
                        Text(verbatim: "By")
                        inlineWebsiteLink(credit.provider)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(group.humans) { contributor in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    creditIcon(contributor.kind.symbol, label: localized("Human contributors"))
                    MacOS15HoverProfileLink(name: contributor.name, homepages: contributor.homepages)
                }
            }
        }
    }

    private func creditIcon(_ symbol: String, label: String) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(.secondary)
            .frame(width: typography.room(16))
            .accessibilityLabel(label)
    }

    private func inlineWebsiteLink(_ homepage: ProfileHomepage) -> some View {
        Link(destination: homepage.destination) {
            HStack(spacing: 3) {
                Text(verbatim: homepage.title)
                Image(systemName: "arrow.up.right")
                    .font(typography.font(.caption2).weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private var versionCard: some View {
        let shape = RoundedRectangle(cornerRadius: MacOS15SettingsSurface.groupCornerRadius)
        return VStack(spacing: 0) {
            appIdentity
            if distribution.checksForUpdates {
                Divider()
                softwareUpdate
            }
        }
        .clipShape(shape)
        .macOS15SettingsSurface(in: shape)
        .overlay {
            shape.strokeBorder(.primary.opacity(accessibility.increasedContrast ? 0.30 : 0.10))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var appIdentity: some View {
        let layout =
            typography.usesLargeLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            Group {
                if let icon = Self.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    MacOS15AppSymbolView(pointSize: 38)
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .frame(width: max(64, typography.points(36)), height: max(64, typography.points(36)))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { identityHeading }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) { identityHeading }
                }
                Text(appSummary)
                    .font(typography.font(.callout))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .macOS15SettingsSearchAnchor("version")
        .padding(16)
        .background {
            Rectangle().fill(.tint.opacity(0.07))
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing))
        }
    }

    @ViewBuilder
    private var identityHeading: some View {
        Text(AppIdentity.displayName)
            .font(typography.font(.title2).weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
        if let number = buildInfo.versionNumber {
            MacOS15VersionLabel(
                version: "\(localized("Version")) \(number)", buildInfo: buildInfo, typography: typography)
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
            let layout =
                typography.usesLargeLayout
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                updateSummary
                checkForUpdatesButton
            }
            .macOS15SettingsSearchAnchor("checkUpdates")
            .padding(.vertical, 14)

            Divider()

            MacOS15SettingsPicker(
                localized("Update channel"),
                selection: Binding(get: { updateChecker.channel }, set: updateChecker.setChannel),
                display: \.selectionTitle
            ) {
                ForEach(UpdateChannel.allCases, id: \.self) { channel in
                    Text(channel.selectionTitle).tag(channel)
                }
            }
            .padding(.vertical, 10)
            .macOS15SettingsSearchAnchor("updateChannel")

            Divider()

            Toggle(localized("Check for updates at launch"), isOn: $general.checkForUpdates)
                .toggleStyle(MacOS15SettingsToggleStyle())
                .padding(.vertical, 10)
        }
        .padding(.horizontal, 16)
    }

    private var updateSummary: some View {
        HStack(spacing: 12) {
            updateStatusIcon
                .font(typography.font(.body))
                .frame(width: typography.room(32), height: typography.room(32))
                .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(localized("Software Update"))
                    .font(typography.font(.headline))
                    .accessibilityAddTraits(.isHeader)
                Text(updateStatus)
                    .font(typography.font(.callout))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let release = updateChecker.availableRelease {
                    Link(destination: release.page) {
                        Label(localized("Download update on GitHub"), systemImage: "arrow.up.right")
                            .font(typography.font(.callout).weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var checkForUpdatesButton: some View {
        let disabled = !updateChecker.canCheckForUpdates || updateChecker.state == .checking
        return Label(localized("Check for updates"), systemImage: "arrow.clockwise")
            .beButton { updateChecker.checkNow() }
            .macOS15SettingsAction()
            .disabled(disabled)
            .fixedSize(horizontal: false, vertical: true)
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

    private var upstreamCredit: AttributedString {
        var text = AttributedString(localized("Whisk is the upstream project for WhiskyMac."))
        guard let range = text.range(of: "Whisk") else { return text }
        var link = AttributedString("Whisk")
        var arrow = AttributedString("\u{00A0}↗")
        arrow.font = typography.font(.caption2).weight(.semibold)
        link.append(arrow)
        link.link = upstreamURL
        text.replaceSubrange(range, with: link)
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
            actionGroup(nil) {
                MacOS15HoverProfileLink(name: "Lin Shay", homepages: ProfileHomepage.developerHomepages)
                    .font(typography.font(.headline))
                Text(
                    localized(
                        "LinShay (琳曦) independently maintains WhiskyMac, with a focus on a more comfortable clipboard experience on macOS."
                    ))
            }
            .macOS15SettingsSearchAnchor("developer")
            actionGroup(localized("Support development")) {
                ForEach(ProfileHomepage.supportHomepages(for: distribution)) { homepage in
                    MacOS15ExternalHomepageLink(title: homepage.title, destination: homepage.destination)
                }
            }
        }
    }

    private func githubLink(_ title: String, destination: URL) -> some View {
        MacOS15ExternalHomepageLink(title: title, destination: destination)
    }

    private func repositoryCredit(_ title: String, repository: String, purpose: String) -> some View {
        HStack(alignment: .center, spacing: 4) {
            githubLink(title, destination: URL(string: "https://github.com/\(repository)")!)
            Text(purpose)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionGroup<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        group(title, content: content).macOS15SettingsAction()
    }

    private func group<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(typography.font(.headline)) }
            VStack(alignment: .leading, spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .macOS15SettingsSurface(
                    in: RoundedRectangle(cornerRadius: MacOS15SettingsSurface.groupCornerRadius, style: .continuous))
        }
    }
}
