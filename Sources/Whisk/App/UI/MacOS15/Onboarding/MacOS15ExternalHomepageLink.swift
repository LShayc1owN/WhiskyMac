// WhiskyMac: modified or added 2026-11-11 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct MacOS15ExternalHomepageLink: View {
    private static let githubIcon = AppResources.bundle.url(forResource: "GitHub", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))
    private static let coffeeIcon = AppResources.bundle.url(forResource: "BuyMeACoffee", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 6) {
                if let icon = SupportLinkIcon.image(for: destination) {
                    Image(nsImage: icon)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                } else if destination.host?.lowercased() == "github.com", let icon = Self.githubIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .renderingMode(.template)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                } else if destination.host?.lowercased() == "buymeacoffee.com", let icon = Self.coffeeIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                } else if destination.scheme?.lowercased() == "mailto" {
                    Image(systemName: "envelope")
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "link").accessibilityHidden(true)
                }
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.bordered)
    }
}

/// Hover and click both reveal the person's homepages; keyboard activation works too.
struct MacOS15HoverProfileLink: View {
    let name: String
    let homepages: [ProfileHomepage]
    @State private var isPresented = false
    @State private var dismissal: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 3) {
            Text(name)
            Image(systemName: "arrow.up.right")
                .font(.caption2.weight(.semibold))
                .accessibilityHidden(true)
        }
        .beButton {
            dismissal?.cancel()
            isPresented = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .macOS15LinkPointer()
        .help(localized("View profile links"))
        .accessibilityHint(localized("View profile links"))
        .onHover { inside in
            if inside {
                dismissal?.cancel()
                isPresented = true
            } else {
                scheduleDismissal()
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(homepages) { homepage in
                    MacOS15ExternalHomepageLink(title: homepage.title, destination: homepage.destination)
                }
            }
            .buttonStyle(.bordered)
            .padding(12)
            .onHover { inside in
                if inside { dismissal?.cancel() } else { scheduleDismissal() }
            }
        }
        .onDisappear {
            dismissal?.cancel()
            dismissal = nil
            isPresented = false
        }
    }

    private func scheduleDismissal() {
        dismissal?.cancel()
        dismissal = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isPresented = false
        }
    }
}
