import AppKit
import SwiftUI
import Testing

@testable import Whisk

@MainActor
@Suite struct PanelThumbnailPreparationTests {
    private final class WorkerCalls: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        var count: Int { lock.withLock { calls } }

        func record() {
            #expect(!Thread.isMainThread)
            lock.withLock { calls += 1 }
        }
    }

    private func bitmap(red: CGFloat, blue: CGFloat) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 80, height: 64, bitsPerComponent: 8, bytesPerRow: 80 * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: red, green: 0, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 64))
        return try #require(context.makeImage())
    }

    private func nextMainTurn() async {
        await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } }
    }

    private func drain(_ queue: OperationQueue) async {
        await withCheckedContinuation { done in queue.addBarrierBlock { done.resume() } }
        await nextMainTurn()
    }

    private func request(_ id: UUID, _ content: BinaryContent) -> ImageThumbnailRequest {
        ImageThumbnailRequest(id: id, content: content, maxPixelSize: ImageThumbnailRequest.cardPixelLimit)
    }

    @Test func preparation_counts_opening_slots_and_skips_hidden_originals_and_rtf_variants() {
        let clock = FakeClock()
        let reference = StoredBytes(
            key: "opaque", byteCount: 12,
            read: {
                Issue.record("Listing thumbnails opened an original"); return Data()
            }, matches: { _ in false })
        let formats = (0..<2).map { _ in
            ClipboardItem(
                id: UUID(), payload: .text("formatted"), source: nil, copiedAt: clock.now(),
                isPinned: false, richText: .stored(reference))
        }
        let hidden = anItem(.storedImage(reference), pinned: true).withPinnedMetadata(
            PinnedMetadata(hidesContent: true))
        let image = anItem(.storedImage(reference))
        let files = anItem(.fileReferences(["/drawing.svg", "/second.pdf"]))
        let disk = InMemoryHistoryStore()
        disk.stored = [hidden] + formats + [anItem(.text("other")), image, files]
        let board = ScriptedPasteboard()
        let controller = ClipboardController(pasteboard: board, store: disk, clock: clock, present: { _ in })
        controller.search("other")
        #expect(controller.openingThumbnailItems(slotLimit: 0).isEmpty)
        #expect(controller.openingThumbnailItems(slotLimit: 3).isEmpty)
        #expect(controller.openingThumbnailItems(slotLimit: 4).map(\.id) == [image.id])
        #expect(controller.openingThumbnailItems(slotLimit: 5).map(\.id) == [image.id, files.id])
        controller.setHistoryHiding(HistoryHidingRule(cutoff: clock.now(), categories: [.image]))
        #expect(controller.openingThumbnailItems(slotLimit: 3).map(\.id) == [files.id])
        controller.toggleHistoryVisibility()
        #expect(controller.openingThumbnailItems(slotLimit: 24).isEmpty)
        clock.advance(by: 1)
        board.pendingSnapshots = [PasteboardSnapshot(payload: .fileReferences(["/new.pdf"]), source: nil)]
        controller.pollTick()
        #expect(controller.openingThumbnailItems(slotLimit: 1).map(\.payload) == [.fileReferences(["/new.pdf"])])
        #expect(PanelThumbnailPreparation.slotLimit(width: 1512, stride: 224) == 11)
        #expect(PanelThumbnailPreparation.slotLimit(width: 20000, stride: 100) == 24)
    }

    @Test func prepared_source_pixels_are_in_the_first_draw_on_three_opens_with_one_original_read() async throws {
        _ = NSApplication.shared
        let bytes = try #require(
            NSBitmapImageRep(cgImage: try bitmap(red: 1, blue: 0)).representation(using: .png, properties: [:]))
        let reads = WorkerCalls()
        let reference = StoredBytes(
            key: "red-png", byteCount: bytes.count,
            read: {
                reads.record(); return bytes
            }, matches: { $0 == bytes })
        let item = anItem(.storedImage(reference))
        let queue = OperationQueue()
        let images = ImageThumbnailStore(queue: queue)
        let preparation = PanelThumbnailPreparation(
            images: images, files: FileThumbnailStore(), lightweight: false, protected: false, openingItems: { [item] })
        await nextMainTurn()
        await drain(queue)
        let openingRequest = request(item.id, .stored(reference))
        let ready = try #require(images.cachedImage(for: openingRequest))
        let retainedBytes = images.cachedBytes
        for _ in 0..<3 {
            preparation.setPanelVisible(true)
            // No event loop, async view task, or decode between mounting and sampling.
            let firstDraw = ImageRenderer(
                content:
                    ImageThumbnailView(id: item.id, content: .stored(reference), fills: true, thumbnails: images)
                    .frame(width: 120, height: 80))
            let pixels = NSBitmapImageRep(cgImage: try #require(firstDraw.cgImage))
            let center = try #require(
                pixels.colorAt(x: pixels.pixelsWide / 2, y: pixels.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
            #expect(center.alphaComponent > 0.95 && center.redComponent > 0.9 && center.blueComponent < 0.1)
            let loader = ImageThumbnailLoader()
            var loading = false
            let observer = loader.$isLoading.sink { loading = loading || $0 }
            loader.load(openingRequest, store: images)
            #expect(loader.image(for: openingRequest) === ready && !loading)
            withExtendedLifetime(observer) {}
            preparation.setPanelVisible(false)
            await nextMainTurn()
            #expect(images.cachedBytes == retainedBytes && images.cachedCount == 1)
        }
        #expect(reads.count == 1 && images.pendingCount == 0)
    }

    @Test func shortcut_toggle_draws_a_prepared_card_in_the_new_panel_host_on_each_open() async throws {
        _ = NSApplication.shared
        let png = try #require(
            NSBitmapImageRep(cgImage: try bitmap(red: 1, blue: 1)).representation(using: .png, properties: [:]))
        let item = anItem(.image(png))
        let warmed = await withCheckedContinuation { done in
            ImageThumbnailStore.shared.load(request(item.id, .inline(png))) { done.resume(returning: $0 != nil) }
        }
        try #require(warmed)
        let defaults = try IsolatedDefaults()
        let state = HistoryViewStateStore()
        state.update(HistoryPresenter().present(items: [item], query: "", now: item.copiedAt, selectedID: item.id))
        let panel = PanelController(
            stateStore: state, actions: PanelActionSpy().actions,
            keyBindings: KeyBindingsStore(defaults: defaults.defaults),
            vimBindings: VimBindingsStore(defaults: defaults.defaults), vimMode: { false })
        var windowsAlreadyShown: [Bool] = []
        state.contentCacheVisibility = { [weak panel] visible in
            if visible, let panel { windowsAlreadyShown.append(panel.activeWindow.isVisible) }
        }
        defer { panel.hide() }
        for _ in 0..<2 {
            panel.toggle()
            try #require(panel.activeWindow.isVisible)
            let host = try #require(panel.activeWindow.contentView)
            host.layoutSubtreeIfNeeded()
            let pixels = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: pixels)
            var sourcePixels = 0
            for y in stride(from: 4, to: pixels.pixelsHigh, by: 12) {
                for x in stride(from: 4, to: pixels.pixelsWide, by: 12) {
                    // The window's display profile can shift individual channels. The magenta
                    // source remains distinct from the neutral placeholder and blue selection ring.
                    if let color = pixels.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                        color.redComponent - color.greenComponent > 0.5,
                        color.blueComponent - color.greenComponent > 0.5,
                        color.alphaComponent > 0.9
                    {
                        sourcePixels += 1
                    }
                }
            }
            #expect(sourcePixels > 30)
            panel.toggle()
            #expect(!state.panelVisible && panel.activeWindow.contentView == nil)
        }
        #expect(windowsAlreadyShown == [false, false])
    }

    @Test func opening_during_preparation_joins_one_decode_and_close_discards_offscreen_and_large_previews()
        async throws
    {
        let queue = OperationQueue()
        queue.isSuspended = true
        let calls = WorkerCalls()
        let result = try bitmap(red: 1, blue: 0)
        let images = ImageThumbnailStore(queue: queue) { _, _ in
            calls.record(); return result
        }
        let item = anItem(.image(Data([1])))
        let second = anItem(.image(Data([2])))
        var opening = [item, second]
        let prep = PanelThumbnailPreparation(
            images: images, files: FileThumbnailStore(), lightweight: false, protected: false, openingItems: { opening }
        )
        await nextMainTurn()
        #expect(images.pendingCount == 2)
        opening = [item]
        prep.schedule()
        await nextMainTurn()
        prep.setPanelVisible(true)
        let card = request(item.id, .inline(Data([1])))
        let loader = ImageThumbnailLoader()
        loader.load(card, store: images)
        #expect(images.pendingCount == 1 && loader.isLoading)
        queue.isSuspended = false
        await drain(queue)
        #expect(calls.count == 1 && loader.image(for: card) != nil)
        images.load(ImageThumbnailRequest(id: item.id, data: Data([1]), maxPixelSize: 1024)) { _ in }
        images.load(request(second.id, .inline(Data([2])))) { _ in }
        await drain(queue)
        #expect(images.cachedCount == 3)
        prep.setPanelVisible(false)
        await nextMainTurn()
        #expect(images.cachedCount == 1 && images.cachedImage(for: card) != nil)
    }

    @Test func lightweight_only_loads_while_visible_and_protection_or_pressure_revokes_background_work() async throws {
        let queue = OperationQueue()
        queue.isSuspended = true
        let image = try bitmap(red: 1, blue: 0)
        let calls = WorkerCalls()
        let images = ImageThumbnailStore(queue: queue) { _, _ in
            calls.record(); return image
        }
        let fileQueue = OperationQueue()
        fileQueue.isSuspended = true
        let files = FileThumbnailStore(
            worker: FileThumbnailWorker(
                queue: fileQueue, icon: { _ in nil },
                generate: { _, done in
                    done(image); return {}
                }))
        let item = anItem(.image(Data([1])))
        var selections = 0
        let prep = PanelThumbnailPreparation(images: images, files: files, lightweight: true, protected: false) {
            selections += 1
            return [item, anItem(.fileReferences(["/only-first.svg", "/later.pdf"]))]
        }
        prep.schedule()
        await nextMainTurn()
        #expect(selections == 0 && images.pendingCount == 0 && files.pendingCount == 0)
        prep.setPanelVisible(true)
        images.load(request(item.id, .inline(Data([1])))) { _ in }
        files.load("/only-first.svg")
        queue.isSuspended = false
        fileQueue.isSuspended = false
        await drain(queue)
        await drain(fileQueue)
        #expect(images.cachedCount == 1 && files.thumbnails.count == 1)
        prep.setPanelVisible(false)
        #expect(images.cachedBytes == 0 && files.cachedBytes == 0)
        queue.isSuspended = true
        fileQueue.isSuspended = true
        prep.setLightweightMode(false)
        await nextMainTurn()
        #expect(images.pendingCount == 1 && files.pendingCount == 1)
        prep.setPrivacy(true)
        #expect(images.pendingCount == 0 && files.pendingCount == 0)
        prep.setMemoryPressure(true)
        prep.setPrivacy(false)
        prep.schedule()
        await nextMainTurn()
        #expect(selections == 1)
        prep.setMemoryPressure(false)
        await nextMainTurn()
        #expect(images.pendingCount == 1 && files.pendingCount == 1)
        queue.isSuspended = false
        fileQueue.isSuspended = false
        await drain(queue)
        await drain(fileQueue)
        #expect(calls.count == 2 && files.thumbnails.keys.sorted() == ["/only-first.svg"])
        prep.setMemoryPressure(true)
        #expect(images.cachedBytes == 0 && files.cachedBytes == 0)
        prep.setMemoryPressure(false)
        prep.setLightweightMode(true)
        await nextMainTurn()
        #expect(selections == 2 && images.pendingCount == 0 && files.pendingCount == 0)
    }

    @Test func a_temporary_original_read_failure_during_preparation_can_retry_on_open() async throws {
        let queue = OperationQueue()
        let calls = WorkerCalls()
        let result = try bitmap(red: 1, blue: 0)
        let images = ImageThumbnailStore(queue: queue) { _, _ in result }
        let reference = StoredBytes(
            key: "available-on-second-read", byteCount: 1,
            read: {
                calls.record()
                if calls.count == 1 { throw HistoryStoreError.unreadable("temporarily unavailable") }
                return Data([1])
            }, matches: { $0 == Data([1]) })
        let item = anItem(.storedImage(reference))
        let prep = PanelThumbnailPreparation(
            images: images, files: FileThumbnailStore(), lightweight: false, protected: false, openingItems: { [item] })
        await nextMainTurn()
        await drain(queue)
        #expect(images.cachedCount == 0 && calls.count == 1)
        prep.setPanelVisible(true)
        let card = request(item.id, .stored(reference))
        let loader = ImageThumbnailLoader()
        loader.load(card, store: images)
        await drain(queue)
        #expect(loader.image(for: card) != nil && images.cachedCount == 1 && calls.count == 2)
    }

    @Test func an_oversized_replacement_cannot_leave_the_previous_files_thumbnail_in_the_cache() throws {
        let large = try bitmap(red: 0, blue: 1)
        let small = NSImage(
            cgImage: try #require(large.cropping(to: CGRect(x: 0, y: 0, width: 10, height: 8))), size: .zero)
        let store = FileThumbnailStore(byteLimit: FileThumbnailStore.pixelBytes(small))
        let path = "/synthetic/replaced.svg"
        store.store(small, for: path)
        #expect(store.thumbnail(for: path) === small)
        store.store(NSImage(cgImage: large, size: .zero), for: path)
        #expect(store.image(for: path) == nil && store.cachedBytes == 0)
    }

    @Test func unchanged_finder_file_is_ready_on_reopen_and_an_external_replacement_or_deletion_is_seen() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("whisk-thumbnail-\(UUID()).svg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url, options: .atomic)
        let red = try bitmap(red: 1, blue: 0)
        let blue = try bitmap(red: 0, blue: 1)
        let calls = WorkerCalls()
        let queue = OperationQueue()
        let files = FileThumbnailStore(
            worker: FileThumbnailWorker(queue: queue, icon: { _ in nil }) { _, done in
                calls.record()
                let value = try? Data(contentsOf: url).first
                done(value.map { $0 == 1 ? red : blue })
                return {}
            })
        let item = anItem(.fileReferences([url.path]))
        let prep = PanelThumbnailPreparation(
            images: ImageThumbnailStore(), files: files, lightweight: false, protected: false, openingItems: { [item] })
        await nextMainTurn()
        await drain(queue)
        let ready = try #require(files.thumbnail(for: url.path))
        for _ in 0..<2 {
            prep.setPanelVisible(true)
            queue.isSuspended = true
            files.load(url.path, checkingCachedFile: true)
            #expect(files.image(for: url.path) === ready)
            queue.isSuspended = false
            await drain(queue)
            prep.setPanelVisible(false)
            await nextMainTurn()
        }
        #expect(calls.count == 1)
        try Data([2]).write(to: url, options: .atomic)
        files.load(url.path, checkingCachedFile: true)
        await drain(queue)
        let replacement = try #require(files.thumbnail(for: url.path))
        #expect(replacement !== ready && calls.count == 2)
        let rep = NSBitmapImageRep(
            cgImage: try #require(replacement.cgImage(forProposedRect: nil, context: nil, hints: nil)))
        let color = try #require(rep.colorAt(x: 10, y: 10)?.usingColorSpace(.deviceRGB))
        #expect(color.blueComponent > 0.9 && color.redComponent < 0.1)
        try FileManager.default.removeItem(at: url)
        files.load(url.path, checkingCachedFile: true)
        await drain(queue)
        #expect(files.image(for: url.path) == nil && files.cachedBytes == 0)
    }
}
