import Foundation
import Testing

@testable import Whisk

@MainActor
@Suite struct UpdateCheckerTests {
    private final class Feed {
        struct Request {
            let url: URL
            let completion: (Data?, URLResponse?, Error?) -> Void
        }
        var requests: [Request] = []

        func fetch(_ url: URL, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
            requests.append(Request(url: url, completion: completion))
        }

        func reply(
            to index: Int, status: Int = 200, body: String = "[]", next: String? = nil, error: Error? = nil
        ) async throws {
            try #require(requests.indices.contains(index))
            let request = requests[index]
            let headers = next.map { ["Link": "<\($0)>; rel=\"next\""] }
            let response = HTTPURLResponse(
                url: request.url, statusCode: status, httpVersion: nil, headerFields: headers)
            request.completion(Data(body.utf8), response, error)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @Test func versions_compare_numeric_components_and_rank_stable_above_beta() throws {
        let orderedPairs = [
            ("0.5.1", "0.6.0"), ("0.9.9", "1.0.0"), ("0.5.9", "0.5.10"), ("0.4.9", "0.5.0"),
            ("1.2.0beta2", "v1.2.0-beta.10"), ("1.2.0-beta", "V1.2.0-BETA-2"), ("1.2.0beta10", "1.2.0"),
            ("1.2.9", "1.3.0-beta.1"), ("1.2.0-beta.1", "1.2.0"),
        ]
        for (older, newer) in orderedPairs {
            let olderVersion = try #require(UpdateVersion(older))
            let newerVersion = try #require(UpdateVersion(newer))
            #expect(olderVersion < newerVersion, "\(older) should precede \(newer)")
        }

        for (first, second) in [("0.5.0", "0.5.0"), ("1.2.0", "v1.2"), ("1.2.0beta2", "1.2-beta.2")] {
            let firstVersion = try #require(UpdateVersion(first))
            #expect(firstVersion == UpdateVersion(second))
        }

        for invalid in [
            "", "1.x.3", "1.2..3", "1.2+build", "1.2.0-rc.1", "1.2.0-beta.", "1.2.0-beta.99999999999999999999999",
        ] {
            #expect(UpdateVersion(invalid) == nil)
        }
    }

    @Test func beta_selection_filters_drafts_invalid_tags_and_mislabeled_releases() async throws {
        let sandbox = try IsolatedDefaults()
        let feed = Feed()
        let checker = UpdateChecker(currentVersion: "1.1.0", fetch: feed.fetch, defaults: sandbox.defaults)
        #expect(checker.channel == .release)
        checker.setChannel(.beta)
        #expect(feed.requests.isEmpty)
        #expect(UpdateChecker(defaults: sandbox.defaults).channel == .beta)
        checker.checkNow()
        try await feed.reply(
            to: 0,
            body: """
                [
                  {"tag_name":"v2.1.0","prerelease":false},
                  {"tag_name":"v1.2.0-beta.10","prerelease":true,"html_url":"https://other.example/file"},
                  {"tag_name":"v9.0.0-beta.1","prerelease":true,"draft":true},
                  {"tag_name":"v1.2.0-beta.2","prerelease":true},
                  {"tag_name":"v8.0.0-beta.1","prerelease":false},
                  {"tag_name":"v8.0.0","prerelease":true},
                  {"tag_name":"v8.0.0-rc.1","prerelease":true},
                  {"tag_name":5,"prerelease":true}
                ]
                """)
        #expect(feed.requests.first?.url.path == "/repos/LShayc1owN/WhiskyMac/releases")
        #expect(checker.availableRelease?.version == "1.2.0-beta.10")
        #expect(
            checker.availableRelease?.page.absoluteString
                == "https://github.com/LShayc1owN/WhiskyMac/releases/tag/v1.2.0-beta.10")
    }

    @Test func both_channels_use_the_highest_version_across_all_pages() async throws {
        let sandbox = try IsolatedDefaults()
        let feed = Feed()
        let checker = UpdateChecker(currentVersion: "1.1.0-beta.6", fetch: feed.fetch, defaults: sandbox.defaults)
        checker.setChannel(.all)
        checker.checkNow()
        try await feed.reply(
            to: 0, body: #"[{"tag_name":"v1.2.0-beta.2","prerelease":true}]"#,
            next: "https://api.github.com/repositories/123/releases?per_page=100&page=2")
        #expect(checker.state == .checking)
        #expect(feed.requests.last?.url.path == "/repos/LShayc1owN/WhiskyMac/releases")
        #expect(feed.requests.last?.url.query?.contains("page=2") == true)
        try await feed.reply(to: 1, body: #"[{"tag_name":"v1.2.0"},{"tag_name":"v1.1.0-beta.9","prerelease":true}]"#)
        #expect(checker.availableRelease?.version == "1.2.0")
        checker.checkNow()
        try await feed.reply(to: 2, body: #"[{"tag_name":"v1.3.0beta1","prerelease":true},{"tag_name":"v1.2.0"}]"#)
        #expect(checker.availableRelease?.version == "1.3.0beta1")
    }

    @Test func switching_back_to_release_waits_for_stable_without_offering_a_downgrade() async throws {
        let sandbox = try IsolatedDefaults()
        let feed = Feed()
        let checker = UpdateChecker(currentVersion: "1.2.0-beta.2", fetch: feed.fetch, defaults: sandbox.defaults)
        #expect(checker.canCheckForUpdates)
        checker.setChannel(.all)
        checker.checkNow()
        try await feed.reply(to: 0, body: #"[{"tag_name":"v1.2.0-beta.3","prerelease":true}]"#)
        #expect(checker.availableRelease != nil)

        checker.setChannel(.release)
        #expect(checker.state == .idle && checker.availableRelease == nil)
        checker.checkNow()
        #expect(feed.requests.last?.url.path == "/repos/LShayc1owN/WhiskyMac/releases/latest")
        try await feed.reply(to: 1, body: #"{"tag_name":"v1.1.0"}"#)
        #expect(checker.state == .awaitingStable)
        #expect(checker.availableRelease == nil)
        checker.checkNow()
        try await feed.reply(to: 2, body: #"{"tag_name":"v1.2.0"}"#)
        #expect(checker.availableRelease?.version == "1.2.0")
    }

    @Test func empty_feed_is_distinct_from_invalid_or_failed_responses() async throws {
        let sandbox = try IsolatedDefaults()
        let feed = Feed()
        let logger = RecordingLogger()
        let checker = UpdateChecker(
            currentVersion: "1.2.0", fetch: feed.fetch, logger: logger, defaults: sandbox.defaults)
        checker.setChannel(.beta)
        checker.checkNow()
        try await feed.reply(to: 0)
        #expect(checker.state == .noEligibleRelease && logger.messages.isEmpty)
        checker.checkNow()
        try await feed.reply(to: 1, status: 403)
        #expect(checker.state == .failed && checker.availableRelease == nil)
        #expect(logger.messages == [.updateHTTPRejected] && logger.statuses == [403])
        checker.checkNow()
        try await feed.reply(to: 2, body: "<html>")
        #expect(logger.messages.last == .updateResponseInvalid)
        checker.checkNow()
        try await feed.reply(to: 3, error: URLError(.notConnectedToInternet))
        #expect(logger.messages.last == .updateTransportFailed)
        checker.setChannel(.release)
        checker.checkNow()
        try await feed.reply(to: 4, body: #"{"tag_name":"v1.2.0"}"#)
        #expect(checker.state == .upToDate)
    }

    @Test func old_responses_cannot_replace_new_results_even_after_switching_back() async throws {
        let sandbox = try IsolatedDefaults()
        let feed = Feed()
        let checker = UpdateChecker(currentVersion: "1.0.0", fetch: feed.fetch, defaults: sandbox.defaults)
        checker.checkNow()
        checker.setChannel(.beta)
        checker.checkNow()
        checker.setChannel(.release)
        checker.checkNow()
        try await feed.reply(to: 2, body: #"{"tag_name":"v2.0.0"}"#)
        try await feed.reply(to: 0, body: #"{"tag_name":"v9.0.0"}"#)
        try await feed.reply(
            to: 1, body: #"[{"tag_name":"v9.0.0-beta.1","prerelease":true}]"#,
            next: "https://api.github.com/repositories/123/releases?page=2")
        #expect(feed.requests.count == 3)
        #expect(checker.availableRelease?.version == "2.0.0")
    }

    @Test func fallback_restarts_a_partial_list_and_each_channel_has_its_own_launch_throttle() async throws {
        let sandbox = try IsolatedDefaults()
        let feed = Feed()
        let stableBackup = try #require(URL(string: "https://updates.example.test/latest.json"))
        let listBackup = try #require(URL(string: "https://updates.example.test/releases.json"))
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let checker = UpdateChecker(
            currentVersion: "1.0.0", fetch: feed.fetch, backupAPI: stableBackup, backupReleasesAPI: listBackup,
            defaults: sandbox.defaults, now: { now })
        sandbox.defaults.set(now, forKey: "updateLastAttempt")
        checker.checkNow(automatic: true)
        #expect(feed.requests.isEmpty)

        checker.setChannel(.beta)
        checker.checkNow(automatic: true)
        checker.checkNow()
        #expect(feed.requests.count == 1)
        try await feed.reply(
            to: 0, body: #"[{"tag_name":"v9.0.0-beta.1","prerelease":true}]"#,
            next: "https://api.github.com/repositories/123/releases?page=2")
        try await feed.reply(to: 1, status: 503)
        #expect(feed.requests.last?.url.host == listBackup.host)
        #expect(feed.requests.last?.url.path == listBackup.path)
        #expect(feed.requests.last?.url.query?.contains("page=1") == true)
        try await feed.reply(to: 2, body: #"[{"tag_name":"v1.2.0-beta.1","prerelease":true}]"#)
        #expect(checker.availableRelease?.version == "1.2.0-beta.1")
        checker.checkNow(automatic: true)
        #expect(feed.requests.count == 3)

        checker.setChannel(.release)
        checker.checkNow(automatic: true)
        #expect(feed.requests.count == 3)
        checker.checkNow()
        try await feed.reply(to: 3, error: URLError(.notConnectedToInternet))
        #expect(feed.requests.last?.url == stableBackup)
        try await feed.reply(to: 4, body: #"{"tag_name":"v1.2.0"}"#)
        #expect(checker.availableRelease?.version == "1.2.0")
        #expect(UpdateChecker.backupAPI == nil && UpdateChecker.backupReleasesAPI == nil)
    }

    @Test func app_store_and_builds_without_a_version_do_not_request_updates() throws {
        let sandbox = try IsolatedDefaults()
        let feed = Feed()
        let appStore = UpdateChecker(
            currentVersion: "1.0.0", fetch: feed.fetch, defaults: sandbox.defaults, distribution: .appStore)
        let bare = UpdateChecker(currentVersion: nil, fetch: feed.fetch, defaults: sandbox.defaults)
        #expect(!appStore.canCheckForUpdates && !bare.canCheckForUpdates)
        appStore.setChannel(.all)
        appStore.checkNow()
        appStore.checkNow(automatic: true)
        bare.checkNow()
        #expect(feed.requests.isEmpty)
    }
}
