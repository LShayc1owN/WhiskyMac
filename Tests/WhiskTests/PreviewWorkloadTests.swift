import Foundation
import LinkPresentation
import Testing

@testable import Whisk

@MainActor
@Suite struct LinkPreviewScheduling {
    private final class Fetches {
        var started: [String] = []
        var cancelled: [String] = []
        var completions: [(LPLinkMetadata?) -> Void] = []

        func start(url: URL, completion: @escaping (LPLinkMetadata?) -> Void) -> LinkPreviewStore.CancelFetch {
            started.append(url.absoluteString)
            completions.append(completion)
            return { self.cancelled.append(url.absoluteString) }
        }
    }

    private func deliverCallbacks() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test func two_active_addresses_share_consumers_and_abandoned_queue_entries_never_start() async throws {
        let fetches = Fetches()
        let store = LinkPreviewStore(fetch: fetches.start)
        let urls = (0..<12).map { "https://example.invalid/\($0)" }
        let tickets = try urls.map { url in try #require(store.load(url)) }
        let overlay = try #require(store.load(urls[0]))
        #expect(fetches.started == Array(urls.prefix(2)))
        #expect(store.pendingCount == urls.count)
        store.cancel(tickets[0])
        #expect(fetches.cancelled.isEmpty)
        store.cancel(tickets[2])
        store.cancel(overlay)
        #expect(fetches.started.last == urls[3])
        #expect(fetches.cancelled == [urls[0]])
        fetches.completions[1](nil)
        await deliverCallbacks()
        #expect(store.preview(for: urls[1])?.hasContent == false)
        #expect(fetches.started == [urls[0], urls[1], urls[3], urls[4]])
        #expect(store.activeCount == 2)
        store.releaseCache()
        #expect(store.pendingCount == 0)
        #expect(store.previews.isEmpty)
    }

    @Test func a_cancelled_callback_cannot_replace_the_reopened_request_or_show_a_hidden_link() async throws {
        let fetches = Fetches()
        let store = LinkPreviewStore(fetch: fetches.start)
        let a = "https://example.invalid/a"
        let b = "https://example.invalid/b"
        _ = try #require(store.load(a))
        _ = try #require(store.load(b))
        store.setHiddenAddresses([a])
        #expect(!store.allowsPreview(for: a))
        #expect(store.load(a) == nil)
        #expect(fetches.cancelled == [a])
        store.setHiddenAddresses([])
        _ = try #require(store.load(a))
        fetches.completions[0](nil)
        await deliverCallbacks()
        #expect(store.pendingCount == 2)
        #expect(store.preview(for: a) == nil)
        store.setPrivacy(true)
        fetches.completions[2](nil)
        await deliverCallbacks()
        #expect(store.previews.isEmpty)
        #expect(store.pendingCount == 0)
        #expect(store.load(a) == nil)
        store.setPrivacy(false)
        _ = try #require(store.load(a))
        store.setEnabled(false)
        #expect(store.pendingCount == 0)
        store.setEnabled(true)
        #expect(store.allowsPreview(for: a))
    }
}

@Suite struct PreviewReading {
    @Test func caps_and_task_cancellation_are_checked_before_opening_an_original() async {
        let reader = RichTextPreviewReader()
        let unneeded = BinaryContent.stored(
            StoredBytes(
                key: "unneeded", byteCount: 100,
                read: {
                    Issue.record("Unexpected original read"); return Data()
                },
                matches: { _ in false }))
        #expect(await reader.read(unneeded, maximumBytes: 99) == nil)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await reader.read(unneeded, maximumBytes: 100)
        }
        #expect(await cancelled.value == nil)
        let bytes = Data(#"{\rtf1\ansi\b Bold}"#.utf8)
        let wanted = BinaryContent.stored(
            StoredBytes(
                key: "wanted", byteCount: bytes.count, read: { bytes }, matches: { $0 == bytes }))
        #expect(await reader.read(wanted, maximumBytes: bytes.count) == bytes)
    }
}
