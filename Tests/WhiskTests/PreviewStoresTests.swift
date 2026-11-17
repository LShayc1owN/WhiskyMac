import AppKit
import LinkPresentation
import Testing

@testable import Whisk

@MainActor
@Suite struct LinkPreviewAssembly {
    @Test func no_metadata_assembles_an_empty_preview_at_once() {
        var assembled: LinkPreview?

        LinkPreviewStore.assemble(metadata: nil, host: "example.com") { assembled = $0 }

        #expect(assembled?.host == "example.com")
        #expect(assembled?.hasContent == false)
    }

    @Test func metadata_with_a_title_and_an_icon_assembles_both() async {
        let metadata = LPLinkMetadata()
        metadata.title = "Whisk"
        metadata.iconProvider = NSItemProvider(object: ViewFixtures.swatch)

        let assembled: LinkPreview? = await withCheckedContinuation { continuation in
            LinkPreviewStore.assemble(metadata: metadata, host: "example.com") { continuation.resume(returning: $0) }
        }

        #expect(assembled?.title == "Whisk")
        #expect(assembled?.icon != nil)
        #expect(assembled?.image == nil)
    }

    @Test func a_provider_that_cannot_yield_an_image_yields_nil() async {
        let text = NSItemProvider(object: "just text" as NSString)

        let fromText: NSImage? = await withCheckedContinuation { continuation in
            LinkPreviewStore.loadImage(from: text) { continuation.resume(returning: $0) }
        }
        let fromNothing: NSImage? = await withCheckedContinuation { continuation in
            LinkPreviewStore.loadImage(from: nil) { continuation.resume(returning: $0) }
        }

        #expect(fromText == nil)
        #expect(fromNothing == nil)
    }

    // What the loader itself does — LinkPresentation on a real address —
    // stays out of the suite: the service does not answer on CI runners.
    @Test func loading_skips_bad_addresses_and_previews_already_held() {
        let store = LinkPreviewStore()
        let address = "https://example.com/held"
        store.store(LinkPreview(title: "Held", host: "example.com", icon: nil, image: nil), for: address)

        store.load("not a url")
        store.load(address)

        #expect(store.preview(for: "not a url") == nil)
        #expect(store.preview(for: address)?.title == "Held")
    }
}

@MainActor
@Suite struct LinkPreviewOptOut {
    @Test func switched_off_the_store_neither_fetches_nor_shows_what_it_already_holds() {
        let store = LinkPreviewStore()
        let address = "https://example.com/private"
        store.store(LinkPreview(title: "Private", host: "example.com", icon: nil, image: nil), for: address)
        #expect(store.preview(for: address) != nil)

        store.setEnabled(false)
        store.load("https://example.com/another")

        #expect(!store.isEnabled)
        #expect(store.preview(for: address) == nil)
        #expect(store.previews["https://example.com/another"] == nil)

        store.setEnabled(true)
        #expect(store.preview(for: address)?.title == "Private")
    }
}

@MainActor
@Suite struct PreviewCacheBounds {
    @Test func the_link_and_thumbnail_caches_let_everything_go_past_their_limit() {
        // Instances of their own: the shared ones serve other suites
        // concurrently.
        let links = LinkPreviewStore()
        let files = FileThumbnailStore()
        let empty = LinkPreview(title: nil, host: nil, icon: nil, image: nil)

        for index in 0..<(LinkPreviewStore.maximumCount + 1) {
            links.store(empty, for: "https://example.com/bound/\(index)")
        }
        for index in 0..<(FileThumbnailStore.maximumCount + 1) {
            files.store(ViewFixtures.swatch, for: "/nonexistent/bound/\(index)")
        }

        #expect(links.previews.count <= LinkPreviewStore.maximumCount)
        #expect(files.thumbnails.count <= FileThumbnailStore.maximumCount)
        #expect(links.preview(for: "https://example.com/bound/\(LinkPreviewStore.maximumCount)") != nil)
        #expect(files.thumbnail(for: "/nonexistent/bound/\(FileThumbnailStore.maximumCount)") != nil)
    }

    @Test func link_preview_images_are_downscaled_before_they_land() {
        let links = LinkPreviewStore()
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        let large = NSImage(size: NSSize(width: 1200, height: 800))
        large.addRepresentation(bitmap!)

        links.store(LinkPreview(title: nil, host: nil, icon: nil, image: large), for: "https://example.com/large")

        let held = try! #require(links.preview(for: "https://example.com/large")?.image)
        #expect(max(held.size.width, held.size.height) <= LinkPreviewStore.maximumImageDimension)
        #expect(links.cachedBytes > 0)
        #expect(links.cachedBytes <= LinkPreviewStore.maximumBytes)
    }

    @Test func byte_budgets_evict_the_least_recently_used_image() {
        let singleCost = LinkPreviewStore.pixelBytes(ViewFixtures.swatch)
        #expect(singleCost > 0)
        let links = LinkPreviewStore(countLimit: 16, byteLimit: singleCost)
        let preview = LinkPreview(title: nil, host: nil, icon: nil, image: ViewFixtures.swatch)

        links.store(preview, for: "https://example.com/a")
        links.store(preview, for: "https://example.com/b")
        #expect(links.previews.keys.sorted() == ["https://example.com/b"])
        #expect(links.cachedBytes == singleCost)

        _ = links.preview(for: "https://example.com/b")
        links.store(preview, for: "https://example.com/c")
        #expect(links.previews.keys.sorted() == ["https://example.com/c"])
    }

    @Test func one_image_larger_than_the_whole_budget_is_not_kept() {
        let links = LinkPreviewStore(countLimit: 16, byteLimit: 1)
        links.store(
            LinkPreview(title: nil, host: nil, icon: nil, image: ViewFixtures.swatch),
            for: "https://example.com/big")
        #expect(links.previews.isEmpty)
        #expect(links.cachedBytes == 0)
    }
}

@MainActor
@Suite struct FileThumbnailStorage {
    // Generating a thumbnail — QuickLook on a real file — stays out of the
    // suite: the service does not answer on CI runners.
    @Test func a_thumbnail_already_held_is_neither_regenerated_nor_lost() {
        let store = FileThumbnailStore()
        let path = "/nonexistent/whisk/held.txt"
        let held = ViewFixtures.swatch
        #expect(store.thumbnail(for: path) == nil)

        store.store(held, for: path)
        store.load(path)

        #expect(store.thumbnail(for: path) === held)
    }

    @Test func the_byte_budget_evicts_the_least_recently_used_thumbnail() {
        let singleCost = FileThumbnailStore.pixelBytes(ViewFixtures.swatch)
        #expect(singleCost > 0)
        let store = FileThumbnailStore(countLimit: 16, byteLimit: singleCost)

        store.store(ViewFixtures.swatch, for: "/nonexistent/a")
        store.store(ViewFixtures.swatch, for: "/nonexistent/b")
        #expect(store.thumbnails.keys.sorted() == ["/nonexistent/b"])
        #expect(store.cachedBytes == singleCost)

        _ = store.thumbnail(for: "/nonexistent/b")
        store.store(ViewFixtures.swatch, for: "/nonexistent/c")
        #expect(store.thumbnails.keys.sorted() == ["/nonexistent/c"])
    }
}
