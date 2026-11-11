// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Darwin
import SwiftUI
import Testing

@testable import Whisk

@Suite struct FilterGlassGeometry {
    private func observation(_ x: CGFloat, width: CGFloat = 100, viewport: CGFloat = 600) -> FilterChipViewport {
        .measure(frame: CGRect(x: x, y: 0, width: width, height: 30), viewportWidth: viewport)
    }

    @Test func unmeasured_geometry_does_not_mount_glass() {
        #expect(observation(0, viewport: 0) == .unknown)
        #expect(observation(.nan) == .unknown)
        #expect(!FilterChipViewport.unknown.keepsGlass(previouslyMounted: true))
    }

    @Test func both_edges_use_preload_and_retention_with_selection_zoom() {
        for x: CGFloat in [-200, 750] {
            #expect(observation(x).region == .preload)
            #expect(!observation(x).isVisible)
        }
        for x: CGFloat in [-300, 820] {
            let value = observation(x)
            #expect(value.region == .retain)
            #expect(value.keepsGlass(previouslyMounted: true))
            #expect(!value.keepsGlass(previouslyMounted: false))
        }
        for x: CGFloat in [-350, 850] {
            #expect(!observation(x).keepsGlass(previouslyMounted: true))
        }
        #expect(observation(-102).isVisible)
        #expect(observation(602).isVisible)
    }

    @Test func resizing_and_variable_widths_use_physical_bounds_in_either_direction() {
        #expect(observation(700).region == .preload)
        #expect(observation(700, viewport: 400).region == .outside)
        #expect(observation(-900, width: 1000).isVisible)
        for x: CGFloat in [-500, -200, 0, 650, 820, 1000] {
            #expect(observation(x) == observation(600 - x - 100))
        }
    }

    @Test func disabling_hover_revokes_pending_work_and_reenabling_does_not_restore_it() throws {
        var pending: [DispatchWorkItem] = []
        var fires = 0
        let activation = FilterHoverActivation { _, work in pending.append(work) }
        activation.enter { fires += 1 }
        let old = try #require(pending.first)
        activation.isEnabled = false
        activation.enter { fires += 1 }
        #expect(pending.count == 1)
        activation.isEnabled = true
        old.perform()
        #expect(fires == 0)
        activation.enter { fires += 1 }
        pending.last?.perform()
        #expect(fires == 1)
    }
}

@MainActor
@Suite(.serialized) struct FilterGlassMounting {
    @MainActor
    private final class Model: ObservableObject {
        @Published var count = 200
        @Published var visible = true
        @Published var focus: String?
        var rightToLeft = false
        var animationsEnabled = false

        var filters: FilterBarViewState {
            FilterBarViewState(
                apps: (0..<count).map { index in
                    FilterChip(
                        id: "app-\(index)", label: "Application", sourceBundleID: nil,
                        accessibilityLabel: "Application \(index)", isActive: index == 0,
                        isFocused: focus == "app-\(index)")
                }, kinds: [])
        }
    }

    private struct Row: View {
        @ObservedObject var model: Model
        var body: some View {
            FilterBarView(
                filters: model.filters, isPanelVisible: model.visible,
                onToggleApp: { _ in }, onToggleKind: { _ in }, onFocusApp: { _ in }, onFocusKind: { _ in }
            )
            // Suppress test animations without assigning a read-only system preference.
            .transaction { transaction in
                if !model.animationsEnabled {
                    transaction.animation = nil
                    transaction.disablesAnimations = true
                }
            }
            .environment(\.layoutDirection, model.rightToLeft ? .rightToLeft : .leftToRight)
        }
    }

    private func host(_ model: Model, width: CGFloat = 600) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 60), styleMask: .borderless,
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: Row(model: model))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.setContentSize(NSSize(width: width, height: 60))
        settle(window)
        return window
    }

    private func settle(_ window: NSWindow) {
        for _ in 0..<8 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.025))
        }
    }

    private func backgrounds(_ view: NSView?) -> [BackdropView] {
        guard let view else { return [] }
        return (view as? BackdropView).map { [$0] } ?? view.subviews.flatMap { backgrounds($0) }
    }

    private func scrollView(_ view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView($0) }.first
    }

    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    @Test func glass_count_stays_bounded_as_the_row_grows_and_hidden_panels_release_it() {
        let model = Model()
        let window = host(model)
        defer { window.contentView = nil; window.close() }
        let first = backgrounds(window.contentView).count
        let smallBytes = footprint()
        #expect(first > 0 && first < 20)
        model.count = 1000
        settle(window)
        let large = backgrounds(window.contentView).count
        let largeBytes = footprint()
        #expect(large > 0 && large < 20)
        #expect(abs(large - first) <= 2)
        model.visible = false
        settle(window)
        #expect(backgrounds(window.contentView).isEmpty)
        let hiddenBytes = footprint()
        model.visible = true
        settle(window)
        #expect(!backgrounds(window.contentView).isEmpty)
        print("Filter glass: 200 tags=\(first), 1000 tags=\(large), hidden=0")
        print("Filter process footprint bytes: 200=\(smallBytes), 1000=\(largeBytes), hidden=\(hiddenBytes)")
    }

    @Test(arguments: [false, true], [false, true])
    func distant_keyboard_focus_scrolls_and_discards_the_old_backgrounds(
        rightToLeft: Bool, animationsEnabled: Bool
    ) throws {
        let model = Model()
        model.rightToLeft = rightToLeft
        model.animationsEnabled = animationsEnabled
        let window = host(model)
        defer { window.contentView = nil; window.close() }
        let old = backgrounds(window.contentView)
        let scroll = try #require(scrollView(window.contentView))
        let initialOffset = scroll.contentView.bounds.minX
        model.focus = "app-199"
        settle(window)
        let moved = backgrounds(window.contentView)
        #expect(abs(scroll.contentView.bounds.minX - initialOffset) > 5000)
        #expect(!moved.isEmpty && moved.count < 20)
        #expect(moved.allSatisfy { view in !old.contains(where: { $0 === view }) })
        model.focus = "app-0"
        settle(window)
        #expect(!backgrounds(window.contentView).isEmpty)
        model.count = 2
        settle(window)
        #expect(backgrounds(window.contentView).count == 2)
    }

    @Test func resizing_the_viewport_keeps_visible_glass_and_updates_the_mounting_range() {
        let model = Model()
        let window = host(model)
        defer { window.contentView = nil; window.close() }
        window.setContentSize(NSSize(width: 300, height: 60))
        settle(window)
        let narrow = backgrounds(window.contentView).count
        #expect(narrow > 0 && narrow < 15)
        window.setContentSize(NSSize(width: 900, height: 60))
        settle(window)
        let wide = backgrounds(window.contentView).count
        #expect(wide >= narrow && wide < 25)
    }
}
