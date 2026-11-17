// WhiskyMac: modified or added 2026-11-17 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Combine
import SwiftUI
import Testing

@testable import Whisk

@Suite struct PanelPreparationReuse {
    @Test func reopening_without_changes_does_not_refilter_or_represent_the_history() {
        let clock = FakeClock()
        let store = InMemoryHistoryStore()
        store.stored = [anItem(.text("first")), anItem(.text("second"))]
        var states: [HistoryViewState] = []
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: store, clock: clock, present: { states.append($0) })
        let initial = states.count
        for _ in 0..<20 { controller.panelWillShow() }
        #expect(states.count == initial)
        controller.navigate(.right)
        #expect(states.last?.selectedID == store.stored[1].id)
        controller.panelWillShow()
        #expect(states.last?.selectedID == store.stored[0].id)
        #expect(states.last?.cards.filter(\.isSelected).map(\.id) == [store.stored[0].id])
        #expect(store.saveCount == 0)
        let presented = states.count
        clock.advance(by: 60)
        controller.panelWillShow()
        #expect(states.count == presented + 1)
    }

    @Test func filtering_capture_access_and_localization_invalidate_the_reusable_presentation() {
        let board = ScriptedPasteboard()
        let store = InMemoryHistoryStore()
        store.stored = [anItem(.text("first")), anItem(.text("second"))]
        var state = HistoryViewState.empty
        let controller = ClipboardController(
            pasteboard: board, store: store, clock: FakeClock(), present: { state = $0 })
        controller.search("second")
        #expect(state.cards.count == 1)
        controller.panelWillShow()
        #expect(state.cards.count == 2 && state.query.isEmpty)
        board.pendingSnapshots = [PasteboardSnapshot(payload: .text("new capture"), source: nil)]
        controller.pollTick()
        controller.panelWillShow()
        #expect(state.cards.first?.preview == .text("new capture"))
        board.access = .denied
        controller.panelWillShow()
        #expect(state.accessPrompt != nil)
        board.access = .granted
        controller.panelWillShow()
        #expect(state.accessPrompt == nil)
        controller.refreshLocalization()
        controller.panelWillShow()
        #expect(state.cards.count == 3)
    }

    @Test func time_labels_expire_at_the_copy_time_boundary_even_inside_the_same_wall_clock_minute() {
        let clock = FakeClock(startingAt: Date(timeIntervalSince1970: 120))
        let store = InMemoryHistoryStore()
        store.stored = [anItem(.text("old"), at: Date(timeIntervalSince1970: 30))]
        var presentations = 0
        let controller = ClipboardController(
            pasteboard: ScriptedPasteboard(), store: store, clock: clock, present: { _ in presentations += 1 })
        controller.panelWillShow()
        #expect(presentations == 1)
        clock.advance(by: 30)
        controller.panelWillShow()
        #expect(presentations == 2)
    }

    @Test func large_presentation_prunes_at_most_once_per_cache_even_when_every_minute_changes() {
        let presenter = HistoryPresenter()
        let copied = Date(timeIntervalSince1970: 1_600_000_000)
        let items = (0..<3000).map { anItem(.text("entry \($0)"), at: copied) }
        let initial = presenter.present(items: items, query: "", now: copied.addingTimeInterval(120))
        #expect(presenter.cachePrunePasses == 2)
        let later = presenter.present(items: items, query: "", now: copied.addingTimeInterval(3600))
        #expect(presenter.cachePrunePasses == 3)
        #expect(initial.cards.map(\.preview) == later.cards.map(\.preview))
        let reduced = presenter.present(
            items: (0..<5).map { anItem(.text("new \($0)"), at: copied) }, query: "",
            now: copied.addingTimeInterval(3600))
        #expect(reduced.cards.count == 5 && presenter.cachedPreviewCount == 5)
        #expect(presenter.cachePrunePasses == 5)
    }
}

private final class FilePreviewScript: @unchecked Sendable {
    private let lock = NSLock()
    private var callbacks: [String: (CGImage?) -> Void] = [:]
    private var mainThreadCalls = 0
    var generated: [String] { lock.lock(); defer { lock.unlock() }; return callbacks.keys.sorted() }
    var usedMainThread: Bool { lock.lock(); defer { lock.unlock() }; return mainThreadCalls > 0 }
    func generate(_ path: String, completion: @escaping (CGImage?) -> Void) -> () -> Void {
        lock.lock()
        callbacks[path] = completion
        if Thread.isMainThread { mainThreadCalls += 1 }
        lock.unlock()
        return {}
    }
    func complete(_ path: String, image: CGImage? = nil) {
        lock.lock(); let callback = callbacks.removeValue(forKey: path); lock.unlock()
        callback?(image)
    }
}

@MainActor
@Suite(.serialized) struct FilePreviewResponsiveness {
    private func bitmap() throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    private func settle() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func drain(_ queue: OperationQueue) async {
        await withCheckedContinuation { continuation in queue.addBarrierBlock { continuation.resume() } }
        await settle()
    }

    @Test func local_svg_and_pdf_get_real_thumbnails_without_changing_the_original_files() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("whisk-vector-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let svg = directory.appendingPathComponent("drawing.svg")
        try """
        <svg xmlns="http://www.w3.org/2000/svg" width="320" height="200">
        <circle cx="160" cy="100" r="80" fill="#7d9471"/></svg>
        """.write(to: svg, atomically: true, encoding: .utf8)
        let pdfURL = directory.appendingPathComponent("drawing.pdf")
        let consumer = try #require(CGDataConsumer(url: pdfURL as CFURL))
        var bounds = CGRect(x: 0, y: 0, width: 320, height: 200)
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        pdf.beginPDFPage(nil)
        pdf.setFillColor(CGColor(red: 0.49, green: 0.58, blue: 0.44, alpha: 1))
        pdf.fillEllipse(in: CGRect(x: 80, y: 20, width: 160, height: 160))
        pdf.endPDFPage(); pdf.closePDF()
        let originals = try [svg, pdfURL].map { try Data(contentsOf: $0) }
        let store = FileThumbnailStore()
        defer { store.releaseCache() }
        store.load(svg.path); store.load(pdfURL.path)
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while store.pendingCount > 0, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.pendingCount == 0, "Local Quick Look requests must finish")
        for (index, url) in [svg, pdfURL].enumerated() {
            let image = try #require(
                store.thumbnail(for: url.path), "Quick Look must support the synthetic vector file")
            let bitmap = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(bitmap.width > 0 && bitmap.width <= 404)
            #expect(bitmap.height > 0 && bitmap.height <= 192)
            #expect(try Data(contentsOf: url) == originals[index])
        }
        store.releaseCache()
        #expect(store.pendingCount == 0 && store.cachedBytes == 0 && store.icons.isEmpty && store.thumbnails.isEmpty)
    }

    @Test func a_stalled_vector_file_icon_does_not_delay_panel_preparation_or_closing() async throws {
        _ = NSApplication.shared
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let queue = OperationQueue()
        let worker = FileThumbnailWorker(
            queue: queue,
            icon: { _ in
                #expect(!Thread.isMainThread)
                entered.signal()
                release.wait()
                return nil
            },
            generate: { _, completion in
                completion(nil); return {}
            })
        let thumbnails = FileThumbnailStore(worker: worker)
        thumbnails.load("/synthetic/complex.svg")
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                entered.wait(); continuation.resume()
            }
        }
        defer { release.signal() }
        let sandbox = try IsolatedDefaults()
        let state = HistoryViewStateStore()
        let items = [anItem(.fileReferences(["/synthetic/complex.svg"]))]
        state.update(HistoryPresenter().present(items: items, query: "", now: Date()))
        let controller = PanelController(
            stateStore: state, actions: PanelActionSpy().actions,
            keyBindings: KeyBindingsStore(defaults: sandbox.defaults),
            vimBindings: VimBindingsStore(defaults: sandbox.defaults), vimMode: { false })
        controller.preparePresentation(pins: false, style: nil)
        #expect(controller.activeWindow.contentView != nil)
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: 0, width: 250, height: 220),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(
            rootView: FilePreviewView(
                names: ["complex.svg"], overflow: 0, thumbnailPath: "/synthetic/complex.svg", size: .card,
                store: thumbnails))
        host.sizingOptions = []
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        #expect(host.bounds.width == 250)
        window.contentView = nil; window.close()
        thumbnails.releaseCache()
        #expect(thumbnails.pendingCount == 0 && thumbnails.cachedBytes == 0)
        // The blocked worker has not been released: these operations really
        // completed without waiting for Icon Services, not after a timeout.
        #expect(entered.wait(timeout: .now()) == .timedOut)
    }

    @Test func quicklook_is_bounded_shared_cancelled_offscreen_and_rejects_stale_results() async throws {
        let script = FilePreviewScript()
        let queue = OperationQueue()
        queue.isSuspended = true
        let image = try bitmap()
        let worker = FileThumbnailWorker(queue: queue, icon: { _ in image }, generate: script.generate)
        let store = FileThumbnailStore(worker: worker)
        let first = try #require(store.load("/first.pdf"))
        let shared = try #require(store.load("/first.pdf"))
        store.load("/second.svg")
        let waiting = try #require(store.load("/third.pdf"))
        #expect(store.activeCount == 2 && store.pendingCount == 3)
        store.cancel(first)
        #expect(store.pendingCount == 3)
        store.cancel(waiting)
        queue.isSuspended = false
        await drain(queue)
        #expect(script.generated == ["/first.pdf", "/second.svg"])
        #expect(!script.usedMainThread)
        #expect(store.image(for: "/first.pdf") != nil && store.thumbnail(for: "/first.pdf") == nil)
        store.cancel(shared)
        #expect(store.pendingCount == 1)
        store.releaseCache()
        queue.isSuspended = true
        store.load("/first.pdf")
        script.complete("/first.pdf", image: image)
        script.complete("/second.svg", image: image)
        await settle()
        #expect(store.thumbnails.isEmpty)
        queue.isSuspended = false
        await drain(queue)
        #expect(store.thumbnails.isEmpty)
        store.setPrivacy(true)
        #expect(store.icons.isEmpty && store.image(for: "/first.pdf") == nil)
        #expect(store.load("/private.svg") == nil)
    }

    @Test func finished_thumbnail_replaces_its_icon_within_one_shared_budget_and_store_can_release() async throws {
        let queue = OperationQueue()
        let image = try bitmap()
        let worker = FileThumbnailWorker(
            queue: queue, icon: { _ in image },
            generate: { _, completion in
                completion(image); return {}
            })
        weak var released: FileThumbnailStore?
        var store: FileThumbnailStore? = FileThumbnailStore(byteLimit: image.bytesPerRow * image.height, worker: worker)
        released = store
        store?.load("/a.pdf")
        await drain(queue)
        #expect(store?.icons.isEmpty == true && store?.thumbnails.count == 1)
        #expect(store?.cachedBytes == image.bytesPerRow * image.height)
        store?.load("/b.svg")
        await drain(queue)
        #expect(store?.thumbnails.keys.sorted() == ["/b.svg"])
        store = nil
        #expect(released == nil)
    }

    @Test func each_cached_result_publishes_one_update_even_when_it_evicts_another_image() throws {
        let image = NSImage(cgImage: try bitmap(), size: .zero)
        let store = FileThumbnailStore(byteLimit: FileThumbnailStore.pixelBytes(image))
        var updates = 0
        let observer = store.objectWillChange.sink { updates += 1 }
        store.store(image, for: "/a.svg")
        store.store(image, for: "/b.pdf")
        #expect(updates == 2)
        #expect(store.thumbnails.keys.sorted() == ["/b.pdf"])
        store.releaseCache()
        store.releaseCache()
        #expect(updates == 3)
        withExtendedLifetime(observer) {}
    }

    @Test func stalled_system_cancellation_never_blocks_cache_release_and_late_thumbnails_are_discarded() async throws {
        let cancellationEntered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let queue = OperationQueue()
        let image = try bitmap()
        let worker = FileThumbnailWorker(
            queue: queue, icon: { _ in image },
            generate: { _, _ in
                return {
                    #expect(!Thread.isMainThread)
                    cancellationEntered.signal()
                    release.wait()
                }
            })
        let store = FileThumbnailStore(worker: worker)
        store.load("/stalled.pdf")
        await drain(queue)
        store.releaseCache()
        #expect(store.pendingCount == 0 && store.cachedBytes == 0)
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                cancellationEntered.wait(); continuation.resume()
            }
        }
        release.signal()
    }

    @Test func a_blocked_original_read_does_not_block_panel_cache_controls_or_repopulate_after_close() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("whisk-reader-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.sqlite")
        let database = try SQLiteHistoryStore(databaseURL: url)
        let bytes = Data(repeating: 13, count: 1024)
        try database.save([anItem(.image(bytes))])
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let storage = try SQLiteContentStorage(path: url.path, byteLimit: 4096, countLimit: 2) {
            entered.signal(); release.wait()
        }
        let reference = storage.reference(key: SQLiteContentStorage.digest(bytes), byteCount: bytes.count)
        let read = Task.detached { try reference.read() }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                entered.wait(); continuation.resume()
            }
        }
        storage.setEnabled(false)
        storage.clear()
        storage.setEnabled(true)
        #expect(storage.cachedBytes == 0)
        #expect(storage.reference(key: reference.key, byteCount: bytes.count) === reference)
        #expect(storage.retainedReferences().count == 1)
        release.signal()
        #expect(try await read.value == bytes)
        #expect(storage.readCount == 1 && storage.cachedBytes == 0)
    }
}
