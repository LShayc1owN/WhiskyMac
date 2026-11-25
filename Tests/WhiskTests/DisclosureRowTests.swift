// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite(.serialized) struct DisclosureRowTests {
    @Test func the_rendered_chevron_grows_with_the_interface_font() throws {
        func chevronHeight(at percent: Int) throws -> Int {
            let typography = InterfaceTypography(percent: percent)
            let renderer = ImageRenderer(
                content: MacOS15OnboardingDisclosure("Details") { EmptyView() }
                    .environment(\.interfaceTypography, typography)
                    .frame(width: 360))
            let image = try #require(renderer.nsImage)
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            let trailing = (bitmap.pixelsWide - 60)..<bitmap.pixelsWide
            return (0..<bitmap.pixelsHigh).count { y in
                trailing.contains { x in (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.15 }
            }
        }

        let standard = try chevronHeight(at: 100)
        #expect(standard > 0)
        #expect(try chevronHeight(at: 300) >= standard * 2)
    }

    @Test(arguments: [100, 300])
    func the_title_blank_space_and_chevron_all_toggle_the_disclosure(percent: Int) throws {
        let title = "Details"
        let typography = InterfaceTypography(percent: percent)
        try checkRow(typography: typography) { content in
            MacOS15OnboardingDisclosure(title) { content }
        }
        if #available(macOS 26, *) {
            try checkRow(typography: typography) { content in
                MacOS26OnboardingDisclosure(title) { content }
            }
        }
    }

    private func checkRow<Row: View>(
        typography: InterfaceTypography, row: (AnyView) -> Row
    ) throws {
        _ = NSApplication.shared
        var rowFrame: CGRect?
        var actionFrame: CGRect?
        var actionCount = 0
        let action = Button("Explanation action") { actionCount += 1 }
            .buttonStyle(.plain)
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                actionFrame = $0
            }
            .onDisappear { actionFrame = nil }
        let padding: CGFloat = 16
        let root = row(AnyView(action))
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                rowFrame = $0
            }
            .environment(\.interfaceTypography, typography)
            .transaction { $0.disablesAnimations = true }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(padding)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        let window = NSWindow(
            contentRect: CGRect(x: -10000, y: 0, width: 460, height: 180),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        window.orderFront(nil)
        settle(host)

        #expect(actionFrame == nil)
        let header = try #require(rowFrame)
        #expect(header.width == host.bounds.width - 2 * padding && header.height >= 28)
        // Use the fixture's first row and click inside its title, spacer and chevron.
        let headerY = host.bounds.height - header.midY
        try click(at: CGPoint(x: header.minX + 10, y: headerY), in: window)
        settle(host)
        let frame = try #require(actionFrame)
        try click(at: CGPoint(x: frame.midX, y: host.bounds.height - frame.midY), in: window)
        settle(host)
        #expect(actionCount == 1)
        #expect(actionFrame != nil)

        try click(at: CGPoint(x: header.minX + header.width * 0.75, y: headerY), in: window)
        settle(host)
        #expect(actionFrame == nil)

        try click(at: CGPoint(x: header.maxX - 4, y: headerY), in: window)
        settle(host)
        #expect(actionFrame != nil)
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        view.layoutSubtreeIfNeeded()
    }

    private func click(at point: CGPoint, in window: NSWindow) throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }
}
