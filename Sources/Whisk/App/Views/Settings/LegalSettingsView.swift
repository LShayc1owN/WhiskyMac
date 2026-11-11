// WhiskyMac: modified or added 2026-11-05 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct LegalSettingsView: View {
    @State private var selectedDocument = LegalDocument.license
    @State private var showsOriginal = false

    private static let finderIcon: NSImage? = {
        let workspace = NSWorkspace.shared
        guard let finder = workspace.urlForApplication(withBundleIdentifier: "com.apple.finder") else { return nil }
        return workspace.icon(forFile: finder.path)
    }()

    private var fileURL: URL? { LegalDocuments.url(for: selectedDocument) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localized("Document"))
                    .font(.headline)
                Spacer()
                Picker(localized("Document"), selection: $selectedDocument) {
                    ForEach(LegalDocument.allCases) { document in
                        Text(document.title).tag(document)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
            }

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
                Text(showsOriginal ? previewText : selectedDocument.overview)
                    .font(showsOriginal ? .system(size: 12, design: .monospaced) : .body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .settingsGlass(
                in: RoundedRectangle(cornerRadius: SettingsGlass.groupCornerRadius, style: .continuous))

            if let fileURL {
                Text(fileURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    Button(localized("Open source file")) { NSWorkspace.shared.open(fileURL) }
                    Label {
                        Text(localized("Show in Finder"))
                    } icon: {
                        if let icon = Self.finderIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "folder")
                        }
                    }
                    .beButton { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
                }
                .buttonStyle(SettingsGlassButtonStyle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewText: String {
        guard let fileURL, let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return localized("Legal file is unavailable.")
        }
        return text
    }
}
