// WhiskyMac: modified or added 2026-11-05 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct AboutSettingsView: View {
    let section: SettingsSectionID
    @ObservedObject var updateChecker = UpdateChecker()
    @ObservedObject var general = GeneralSettingsStore()
    @ObservedObject var search = SettingsSearchModel()

    private let projectURL = URL(string: "https://github.com/LShayc1owN/WhiskyMac")!
    private let developerURL = URL(string: "https://github.com/LShayc1owN")!
    private let upstreamURL = URL(string: "https://github.com/nathan-poncet/whisk")!
    private let issuesURL = URL(string: "https://github.com/LShayc1owN/WhiskyMac/issues/new")!

    private var developerHomepages: [ProfileHomepage] {
        [ProfileHomepage(title: localized("Lin Shay on GitHub"), destination: developerURL)]
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
            group(localized("Version and introduction")) {
                Text(localized("WhiskyMac is a native clipboard history app for macOS, based on Whisk."))
                Text(
                    "\(localized("Version")) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")"
                )
                .foregroundStyle(.secondary)
                if Distribution.current.checksForUpdates {
                    HStack(spacing: 16) {
                        Button(localized("Check for updates")) { updateChecker.checkNow() }
                            .disabled(updateChecker.state == .checking)
                        Spacer(minLength: 8)
                        Toggle(localized("Check for updates at launch"), isOn: $general.checkForUpdates)
                            .toggleStyle(.switch)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .settingsSearchAnchor("checkUpdates")
                    Text(updateStatus).font(.caption).foregroundStyle(.secondary)
                    if updateChecker.availableVersion != nil, let url = UpdateChecker.releasesPage {
                        Link(localized("Download update on GitHub"), destination: url)
                    }
                }
            }
            .settingsSearchAnchor("version")
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
                    ForEach(["简体中文", "English", "Français", "Deutsch", "Italiano"], id: \.self) { language in
                        GridRow(alignment: .firstTextBaseline) {
                            Text("\(language):")
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    inlineWebsiteLink("ChatGPT", destination: URL(string: "https://chatgpt.com/")!)
                                    Text("From")
                                    inlineWebsiteLink("OpenAI", destination: URL(string: "https://openai.com/")!)
                                }
                                if language == "简体中文" {
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
                Button(localized("Corrections and feedback")) {}
                    .disabled(true)
                Button(localized("Additional contact")) {}
                    .disabled(true)
                Text(localized("More feedback and contact options will be added when their addresses are available."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .settingsSearchAnchor("feedback")
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
        case .idle: return localized("Updates are downloaded from GitHub. Backup source is not configured.")
        case .checking: return localized("Checking for updates…")
        case .upToDate: return localized("You’re up to date.")
        case .available(let version): return String(format: localized("Update available: %@"), version)
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
                Button(localized("Donate")) {}
                    .disabled(true)
                Text(localized("A donation link will be added later."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func githubLink(_ title: String, destination: URL) -> some View {
        ExternalHomepageLink(title: title, destination: destination)
    }

    private func inlineWebsiteLink(_ title: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack(spacing: 3) {
                Text(title)
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
        .buttonStyle(SettingsSurfaceButtonStyle())
    }
}
