// WhiskyMac: modified or added 2026-11-05 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct MacOS15LegalSettingsView: View {
    @Environment(\.interfaceTypography) private var typography

    @State private var selectedDocument = LegalDocument.license
    @State private var showsOriginal = false

    private static let finderIcon: NSImage? = {
        let workspace = NSWorkspace.shared
        guard let finder = workspace.urlForApplication(withBundleIdentifier: "com.apple.finder") else { return nil }
        return workspace.icon(forFile: finder.path)
    }()

    private var fileURL: URL? { LegalDocuments.url(for: selectedDocument) }

    private var minimumReaderHeight: CGFloat { max(140, typography.lineHeight(13) * 4 + 32) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if typography.isStandard {
                    HStack {
                        Text(localized("Document")).font(typography.font(.headline)).accessibilityHidden(true)
                        Spacer()
                        Picker(localized("Document"), selection: $selectedDocument) { documents }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: 280)
                    }
                } else {
                    MacOS15SettingsPicker(localized("Document"), selection: $selectedDocument, display: \.title) {
                        documents
                    }
                }
            }
            .macOS15SettingsSearchAnchor("licenses")

            if typography.isStandard {
                Picker(localized("Reading mode"), selection: $showsOriginal) { readingModes }
                    .pickerStyle(.segmented)
            } else {
                MacOS15SettingsPicker(localized("Reading mode"), selection: $showsOriginal, display: readingModeTitle) {
                    readingModes
                }
            }

            if !showsOriginal {
                Text(localized("The overview is a reading aid. Refer to the original text for the complete terms."))
                    .font(typography.font(.caption))
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(showsOriginal ? previewText : selectedDocument.overview)
                    .font(showsOriginal ? typography.font(size: 12, design: .monospaced) : typography.font(.body))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .id(selectedDocument)
            .id(showsOriginal)
            .frame(minHeight: minimumReaderHeight, idealHeight: minimumReaderHeight, maxHeight: .infinity)
            .macOS15SettingsSurface(
                in: RoundedRectangle(cornerRadius: MacOS15SettingsSurface.groupCornerRadius, style: .continuous))

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
                    Label {
                        fileActionTitle(localized("Open source file"))
                    } icon: {
                        Image(systemName: "doc.fill")
                    }
                    .beButton { NSWorkspace.shared.open(fileURL) }
                    .macOS15SettingsAction()
                    Label {
                        fileActionTitle(localized("Show in Finder"))
                    } icon: {
                        if let icon = Self.finderIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "folder.fill")
                        }
                    }
                    .beButton { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
                    .macOS15SettingsAction()
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private func fileActionTitle(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "arrow.up.right")
                .font(typography.font(.caption2).weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var previewText: String {
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return localized("Legal file is unavailable.")
        }
        return text
    }
}
