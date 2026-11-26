// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
private enum MacOS26AboutLinks {
    static let project = "https://github.com/LShayc1owN/WhiskyMac"
    static let upstream = "https://github.com/nathan-poncet/whisk"
    static let issues = "https://github.com/LShayc1owN/WhiskyMac/issues/new"
    static let feedbackAddress = "connect.whiskymac@outlook.com"
}

@available(macOS 26, *)
struct MacOS26AboutSettings: View {
    @Environment(\.interfaceTypography) private var typography

    let distribution: Distribution
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject var general: GeneralSettingsStore
    @ObservedObject var developerMode: DeveloperModeStore
    let buildInfo: AppBuildInfo

    private static let appIcon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Section {
            identity
                .macOS26SettingsSearchAnchor("version")
            if distribution.checksForUpdates { updateRows }
        }
        Section {
            VStack(alignment: .leading, spacing: 8) {
                externalLink(localized("WhiskyMac on GitHub"), to: MacOS26AboutLinks.project)
                externalLink(localized("Original Whisk on GitHub"), to: MacOS26AboutLinks.upstream)
            }
            .macOS26SettingsSearchAnchor("repositories")
        } header: {
            Text(localized("Source repositories"))
        }
        Section {
            dependencyCredits
                .macOS26SettingsSearchAnchor("dependencies")
        } header: {
            Text(localized("Dependencies and credits"))
        }
        Section {
            translationCredits
                .macOS26SettingsSearchAnchor("translations")
        } header: {
            Text(localized("Translation contributors"))
        }
        Section {
            VStack(alignment: .leading, spacing: 8) {
                externalLink(localized("Report a bug on GitHub"), to: MacOS26AboutLinks.issues)
                externalLink(
                    MacOS26AboutLinks.feedbackAddress,
                    to: "mailto:\(MacOS26AboutLinks.feedbackAddress)"
                )
            }
            .macOS26SettingsSearchAnchor("feedback")
        } header: {
            Text(localized("Feedback"))
        }
        if developerMode.canChange {
            Section {
                Button(
                    developerMode.showsTools
                        ? localized("Disable Developer Mode") : localized("Enable Developer Mode")
                ) {
                    developerMode.toggle()
                }
            }
        }
    }

    private var identity: some View {
        let layout =
            typography.usesLargeLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))
        return layout {
            Group {
                if let icon = Self.appIcon {
                    Image(nsImage: icon).resizable().scaledToFit()
                } else if let symbol = AppSymbol.image(named: AppSymbol.brandName, pointSize: 38) {
                    Image(nsImage: symbol)
                        .renderingMode(.template)
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.tint.opacity(0.1), in: MacOS26SettingsSurface.rounded(minimum: 18))
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
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var identityHeading: some View {
        Text(AppIdentity.displayName)
            .font(typography.font(.title2).weight(.semibold))
            .accessibilityAddTraits(.isHeader)
        if let number = buildInfo.versionNumber {
            MacOS26VersionLabel(
                version: "\(localized("Version")) \(number)", buildInfo: buildInfo, typography: typography)
        }
    }

    @ViewBuilder
    private var updateRows: some View {
        let layout =
            typography.usesLargeLayout
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            updateSummary
            Button(localized("Check for updates"), systemImage: "arrow.clockwise") {
                updateChecker.checkNow()
            }
            .macOS26SettingsAction()
            .disabled(!updateChecker.canCheckForUpdates || updateChecker.state == .checking)
        }
        .macOS26SettingsSearchAnchor("checkUpdates")
        MacOS26MenuRow(
            localized("Update channel"),
            selection: Binding(get: { updateChecker.channel }, set: updateChecker.setChannel), display: \.selectionTitle
        ) {
            ForEach(UpdateChannel.allCases, id: \.self) { channel in
                Text(channel.selectionTitle).tag(channel)
            }
        }
        .macOS26SettingsSearchAnchor("updateChannel")
        Toggle(localized("Check for updates at launch"), isOn: $general.checkForUpdates)
    }

    private var updateSummary: some View {
        HStack(spacing: 12) {
            updateIcon
                .font(typography.font(.body))
                .frame(width: typography.room(32), height: typography.room(32))
                .background(.tint.opacity(0.1), in: .rect(cornerRadius: 8))
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
                    Link(localized("Download update on GitHub"), destination: release.page)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var updateIcon: some View {
        switch updateChecker.state {
        case .checking: ProgressView().controlSize(.small)
        case .idle, .available: Image(systemName: "arrow.down.to.line").foregroundStyle(.tint)
        case .upToDate: Image(systemName: "checkmark").foregroundStyle(.green)
        case .noEligibleRelease, .awaitingStable: Image(systemName: "info.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }

    private var translationCredits: some View {
        let groups = TranslationCredits.byLanguage
        return ViewThatFits(in: .horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(group.products) { credit in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    creditIcon(TranslationCredits.aiProductSymbol, label: localized("AI assistance"))
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Link(credit.product.title, destination: credit.product.destination)
                        Text(verbatim: "By")
                        Link(credit.provider.title, destination: credit.provider.destination)
                    }
                    .buttonStyle(.link)
                }
            }
            ForEach(group.humans) { contributor in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    creditIcon(contributor.kind.symbol, label: localized("Human contributors"))
                    MacOS26DeveloperProfile(name: contributor.name, homepages: contributor.homepages)
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

    private var appSummary: AttributedString {
        let project = "[WhiskyMac](\(MacOS26AboutLinks.project))"
        let upstream = "[Whisk](\(MacOS26AboutLinks.upstream))"
        let summary = localized("\(project) is a clipboard history app based on \(upstream).")
        return (try? AttributedString(markdown: summary)) ?? AttributedString(summary)
    }

    private var dependencyCredits: some View {
        VStack(alignment: .leading, spacing: 8) {
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
    }

    private var upstreamCredit: AttributedString {
        var text = AttributedString(localized("Whisk is the upstream project for WhiskyMac."))
        guard let range = text.range(of: "Whisk") else { return text }
        var link = AttributedString("Whisk")
        var arrow = AttributedString("\u{00A0}↗")
        arrow.font = typography.font(.caption2).weight(.semibold)
        link.append(arrow)
        link.link = URL(string: MacOS26AboutLinks.upstream)
        text.replaceSubrange(range, with: link)
        return text
    }

    private func repositoryCredit(_ title: String, repository: String, purpose: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            externalLink(title, to: "https://github.com/\(repository)")
                .fixedSize()
            Text(purpose)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
}

@available(macOS 26, *)
struct MacOS26DeveloperSettings: View {
    @Environment(\.interfaceTypography) private var typography
    let distribution: Distribution

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                MacOS26DeveloperProfile(name: "Lin Shay", homepages: ProfileHomepage.developerHomepages)
                    .font(typography.font(.headline))
                Text(
                    localized(
                        "LinShay (琳曦) independently maintains WhiskyMac, with a focus on a more comfortable clipboard experience on macOS."
                    )
                )
                .fixedSize(horizontal: false, vertical: true)
            }
            .macOS26SettingsSearchAnchor("developer")
        }
        Section {
            ForEach(ProfileHomepage.supportHomepages(for: distribution)) { homepage in
                externalLink(homepage.title, to: homepage.destination.absoluteString)
            }
        } header: {
            Text(localized("Support development"))
        }
    }
}

@available(macOS 26, *)
private struct MacOS26DeveloperProfile: View {
    let name: String
    let homepages: [ProfileHomepage]
    @State private var isPresented = false
    @State private var dismissal: Task<Void, Never>?

    var body: some View {
        Label(name, systemImage: "arrow.up.right")
            .beButton {
                dismissal?.cancel()
                isPresented = true
            }
            .buttonStyle(.link)
            .help(localized("View profile links"))
            .onHover { hovering in
                if hovering {
                    dismissal?.cancel()
                    isPresented = true
                } else {
                    dismissAfterHover()
                }
            }
            .popover(isPresented: $isPresented) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(homepages) { homepage in
                        externalLink(homepage.title, to: homepage.destination.absoluteString)
                    }
                }
                .padding(12)
                .onHover { hovering in
                    if hovering { dismissal?.cancel() } else { dismissAfterHover() }
                }
            }
            .onDisappear { dismissal?.cancel() }
    }

    private func dismissAfterHover() {
        dismissal?.cancel()
        dismissal = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            isPresented = false
        }
    }
}

@available(macOS 26, *)
@ViewBuilder
private func externalLink(_ title: String, to address: String) -> some View {
    if let destination = URL(string: address) {
        Link(destination: destination) {
            Label {
                Text(title)
            } icon: {
                if let icon = SupportLinkIcon.image(for: destination) {
                    Image(nsImage: icon)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: destination.scheme == "mailto" ? "envelope" : "arrow.up.right")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .macOS26SettingsAction()
    }
}

@available(macOS 26, *)
struct MacOS26LegalSettings: View {
    @Environment(\.interfaceTypography) private var typography

    @ObservedObject var search: SettingsSearchModel
    @State private var document = LegalDocument.license
    @State private var showsOriginal = false

    private var fileURL: URL? { LegalDocuments.url(for: document) }

    private var minimumReaderHeight: CGFloat { max(140, typography.lineHeight(13) * 4 + 32) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if typography.isStandard {
                    HStack {
                        Text(localized("Document")).font(typography.font(.headline)).accessibilityHidden(true)
                        Spacer()
                        Picker(localized("Document"), selection: $document) { documents }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 280)
                    }
                } else {
                    MacOS26MenuRow(localized("Document"), selection: $document, display: \.title) { documents }
                }
            }
            .macOS26SettingsSearchAnchor("licenses")

            if typography.isStandard {
                Picker(localized("Reading mode"), selection: $showsOriginal) { readingModes }
                    .pickerStyle(.segmented)
            } else {
                MacOS26MenuRow(localized("Reading mode"), selection: $showsOriginal, display: readingModeTitle) {
                    readingModes
                }
            }

            if !showsOriginal {
                Text(localized("The overview is a reading aid. Refer to the original text for the complete terms."))
                    .font(typography.font(.caption))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(showsOriginal ? originalText : document.overview)
                    .font(showsOriginal ? typography.font(size: 12, design: .monospaced) : typography.font(.body))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .id(document)
            .id(showsOriginal)
            .frame(minHeight: minimumReaderHeight, idealHeight: minimumReaderHeight, maxHeight: .infinity)
            .background(.fill.tertiary, in: MacOS26SettingsSurface.rounded(minimum: 22))

            if let fileURL {
                Text(fileURL.path)
                    .font(typography.font(.caption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                let layout =
                    typography.usesLargeLayout
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    fileActionLabel(localized("Open source file"), symbol: "doc.fill")
                        .beButton { NSWorkspace.shared.open(fileURL) }
                        .macOS26SettingsAction()
                    fileActionLabel(localized("Show in Finder"), symbol: "folder.fill")
                        .beButton { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
                        .macOS26SettingsAction()
                }
            }
        }
        .environment(\.macOS26SettingsSearchHighlight, search.highlightedAnchor)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var documents: some View {
        ForEach(LegalDocument.allCases) { document in Text(document.title).tag(document) }
    }

    private func readingModeTitle(_ original: Bool) -> String {
        original ? localized("Original text") : localized("Overview")
    }

    @ViewBuilder private var readingModes: some View {
        Text(readingModeTitle(false)).tag(false)
        Text(readingModeTitle(true)).tag(true)
    }

    private func fileActionLabel(_ title: String, symbol: String) -> some View {
        Label {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "arrow.up.right")
                    .font(typography.font(.caption2).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } icon: {
            Image(systemName: symbol)
        }
    }

    private var originalText: String {
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return localized("Legal file is unavailable.")
        }
        return text
    }
}
