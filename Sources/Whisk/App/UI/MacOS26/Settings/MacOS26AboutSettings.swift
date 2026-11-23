// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
private enum MacOS26AboutLinks {
    static let project = "https://github.com/LShayc1owN/WhiskyMac"
    static let developer = "https://github.com/LShayc1owN"
    static let upstream = "https://github.com/nathan-poncet/whisk"
    static let issues = "https://github.com/LShayc1owN/WhiskyMac/issues/new"
    static let donation = "https://buymeacoffee.com/funclinkrev"
    static let feedbackAddress = "connect.whiskymac@outlook.com"
}

@available(macOS 26, *)
struct MacOS26AboutSettings: View {
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
            translations
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
        HStack(spacing: 16) {
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
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { identityHeading }
                    VStack(alignment: .leading, spacing: 4) { identityHeading }
                }
                Text(appSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var identityHeading: some View {
        Text(AppIdentity.displayName)
            .font(.title2.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
        if let version = buildInfo.versionWithChannel {
            let tint: Color =
                switch buildInfo.channel {
                case .debug: .red
                case .beta: .yellow
                case .release: .green
                }
            Text(verbatim: "\(localized("Version")) \(version)")
                .font(.caption.weight(.medium).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.22), in: .capsule)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var updateRows: some View {
        HStack(spacing: 12) {
            updateIcon
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.1), in: .rect(cornerRadius: 8))
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
                    Link(localized("Download update on GitHub"), destination: release.page)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(localized("Check for updates"), systemImage: "arrow.clockwise") {
                updateChecker.checkNow()
            }
            .buttonStyle(.bordered)
            .disabled(!updateChecker.canCheckForUpdates || updateChecker.state == .checking)
        }
        .macOS26SettingsSearchAnchor("checkUpdates")
        MacOS26MenuRow(
            localized("Update channel"),
            selection: Binding(get: { updateChecker.channel }, set: updateChecker.setChannel)
        ) {
            ForEach(UpdateChannel.allCases, id: \.self) { channel in
                Text(channel.selectionTitle).tag(channel)
            }
        }
        .macOS26SettingsSearchAnchor("updateChannel")
        Toggle(localized("Check for updates at launch"), isOn: $general.checkForUpdates)
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

    private var translations: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            ForEach(AppLanguage.allCases.filter { $0 != .system }) { language in
                GridRow(alignment: .firstTextBaseline) {
                    Text(language.label)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            inlineLink("ChatGPT", to: "https://chatgpt.com/")
                            Text(verbatim: "By")
                            inlineLink("OpenAI", to: "https://openai.com/")
                        }
                        if language == .simplifiedChinese {
                            MacOS26DeveloperProfile(name: "LinShay 琳曦")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inlineLink(_ title: String, to address: String) -> some View {
        if let destination = URL(string: address) {
            Link(title, destination: destination)
        } else {
            Text(title)
        }
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
        if let range = text.range(of: "Whisk") { text[range].link = URL(string: MacOS26AboutLinks.upstream) }
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
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                MacOS26DeveloperProfile(name: "Lin Shay").font(.headline)
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
            externalLink("Buy Me a Coffee", to: MacOS26AboutLinks.donation)
        } header: {
            Text(localized("Support development"))
        }
    }
}

@available(macOS 26, *)
private struct MacOS26DeveloperProfile: View {
    let name: String
    @State private var isPresented = false
    @State private var dismissal: Task<Void, Never>?

    var body: some View {
        Button {
            dismissal?.cancel()
            isPresented = true
        } label: {
            Label(name, systemImage: "arrow.up.right")
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
                externalLink(localized("Lin Shay on GitHub"), to: MacOS26AboutLinks.developer)
                externalLink("Buy Me a Coffee", to: MacOS26AboutLinks.donation)
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
            Label(title, systemImage: destination.scheme == "mailto" ? "envelope" : "arrow.up.right")
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.bordered)
    }
}

@available(macOS 26, *)
struct MacOS26LegalSettings: View {
    @ObservedObject var search: SettingsSearchModel
    @State private var document = LegalDocument.license
    @State private var showsOriginal = false

    private var fileURL: URL? { LegalDocuments.url(for: document) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localized("Document"))
                    .font(.headline)
                    .accessibilityHidden(true)
                Spacer()
                Picker(localized("Document"), selection: $document) {
                    ForEach(LegalDocument.allCases) { document in Text(document.title).tag(document) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
            }
            .macOS26SettingsSearchAnchor("licenses")
            Picker(localized("Reading mode"), selection: $showsOriginal) {
                Text(localized("Overview")).tag(false)
                Text(localized("Original text")).tag(true)
            }
            .pickerStyle(.segmented)

            if !showsOriginal {
                Text(localized("The overview is a reading aid. Refer to the original text for the complete terms."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(showsOriginal ? originalText : document.overview)
                    .font(showsOriginal ? .system(size: 12, design: .monospaced) : .body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .id(document)
            .frame(maxHeight: .infinity)
            .background(.fill.tertiary, in: MacOS26SettingsSurface.rounded(minimum: 22))

            if let fileURL {
                Text(fileURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Button(localized("Open source file")) { NSWorkspace.shared.open(fileURL) }
                    Button(localized("Show in Finder"), systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .environment(\.macOS26SettingsSearchHighlight, search.highlightedAnchor)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var originalText: String {
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return localized("Legal file is unavailable.")
        }
        return text
    }
}
