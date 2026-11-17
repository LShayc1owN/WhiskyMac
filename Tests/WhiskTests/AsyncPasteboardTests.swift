// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Testing

@testable import Whisk

@MainActor
@Suite struct AsyncPasteboardMetadata {
    private func read(_ gateway: AppKitPasteboard) async -> PasteboardSnapshot? {
        await withCheckedContinuation { continuation in
            gateway.readIfChangedAsync { continuation.resume(returning: $0) }
        }
    }

    @Test func queued_service_read_does_not_delay_submission_and_own_write_invalidates_it() async {
        let board = NSPasteboard(name: NSPasteboard.Name("whisk-async-\(UUID())"))
        defer { board.releaseGlobally() }
        let queue = DispatchQueue(label: "whisk.tests.blocked-pasteboard")
        queue.suspend()
        let gateway = AppKitPasteboard(board: board, readQueue: queue)
        board.clearContents()
        board.setString("external copy", forType: .string)
        let result: PasteboardSnapshot? = await withCheckedContinuation { continuation in
            gateway.readIfChangedAsync { continuation.resume(returning: $0) }
            #expect(gateway.access == .granted)
            gateway.write(.text("own write"), rtf: nil)
            queue.resume()
        }
        #expect(result == nil)
        #expect(await read(gateway) == nil)
    }

    @Test func background_metadata_and_original_rtf_are_delivered_once_then_a_new_change_is_read() async {
        let board = NSPasteboard(name: NSPasteboard.Name("whisk-async-\(UUID())"))
        defer { board.releaseGlobally() }
        let gateway = AppKitPasteboard(board: board)
        let rtf = Data("{\\rtf1\\ansi\\b Formatted}".utf8)
        board.declareTypes([.string, .rtf], owner: nil)
        board.setString("Formatted", forType: .string)
        board.setData(rtf, forType: .rtf)
        let snapshot = await read(gateway)
        #expect(snapshot?.payload == .text("Formatted") && snapshot?.rtf == rtf)
        #expect(await read(gateway) == nil)
        board.clearContents()
        board.setString("later", forType: .string)
        #expect(await read(gateway)?.payload == .text("later"))
        #expect(await read(gateway) == nil)
    }

    @Test func a_failed_change_is_consumed_after_three_background_attempts() async {
        let board = NSPasteboard(name: NSPasteboard.Name("whisk-async-\(UUID())"))
        defer { board.releaseGlobally() }
        let gateway = AppKitPasteboard(board: board)
        board.declareTypes([NSPasteboard.PasteboardType("whisk.unreadable")], owner: nil)
        for _ in 0..<4 { #expect(await read(gateway) == nil) }
        board.clearContents()
        board.setString("readable again", forType: .string)
        #expect(await read(gateway)?.payload == .text("readable again"))
    }
}
