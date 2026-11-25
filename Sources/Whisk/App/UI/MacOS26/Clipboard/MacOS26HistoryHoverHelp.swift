// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

@available(macOS 26, *)
struct MacOS26HistoryHoverHelp: ViewModifier {
    let title: String
    let message: String
    var enabled: Bool
    @State private var hovering = false
    @State private var presented = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0 }
            .task(id: hovering && enabled) {
                presented = false
                guard hovering && enabled else { return }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                presented = true
            }
            .background(MacOS26HistoryHoverHelpAnchor(title: title, message: message, presented: presented && enabled))
            .accessibilityHint(message)
    }
}

@available(macOS 26, *)
struct MacOS26HistoryHoverHelpBody: View {
    let title: String
    let message: String

    var typography = InterfaceTypography.standard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(typography.font(.callout).weight(.semibold))
            Text(message).font(typography.font(.callout)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: min(typography.room(280), (NSScreen.main?.visibleFrame.width ?? 720) - 52), alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
    }
}

/// A mouse-transparent child panel can extend above the clipboard without
/// taking keyboard focus from the search field or intercepting a button click.
@available(macOS 26, *)
struct MacOS26HistoryHoverHelpAnchor: NSViewRepresentable {
    @Environment(\.interfaceTypography) private var typography
    let title: String
    let message: String
    let presented: Bool

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.root = MacOS26HistoryHoverHelpBody(title: title, message: message, typography: typography)
        view.presented = presented
        view.updateHelp()
    }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { view.dismiss() }

    final class Anchor: NSView {
        var root = MacOS26HistoryHoverHelpBody(title: "", message: "")
        var presented = false
        private var panel: HelpPanel?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateHelp()
        }
        override func layout() {
            super.layout()
            if presented { updateHelp() }
        }

        func updateHelp() {
            guard presented, let window, window.isVisible else { dismiss(); return }
            let panel = panel ?? HelpPanel()
            self.panel = panel
            panel.appearance = window.appearance
            let host = NSHostingView(rootView: root)
            let size = host.fittingSize
            panel.contentView = host
            let anchor = window.convertToScreen(convert(bounds, to: nil))
            let screen = window.screen?.visibleFrame ?? anchor.insetBy(dx: -1000, dy: -1000)
            let x = min(max(anchor.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
            let y = anchor.maxY + 8 + size.height <= screen.maxY ? anchor.maxY + 8 : anchor.minY - size.height - 8
            panel.setFrame(NSRect(origin: NSPoint(x: x, y: max(screen.minY + 8, y)), size: size), display: true)
            if panel.parent !== window {
                panel.parent?.removeChildWindow(panel)
                window.addChildWindow(panel, ordered: .above)
            }
            panel.orderFront(nil)
        }

        func dismiss() {
            guard let panel else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.contentView = nil
            self.panel = nil
        }
    }

    private final class HelpPanel: NSPanel {
        init() {
            super.init(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            isReleasedWhenClosed = false
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
            ignoresMouseEvents = true
            level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        }
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }
}
