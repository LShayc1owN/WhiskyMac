import Foundation

enum UpdateChannel: String, CaseIterable {
    case release, beta, all

    var selectionTitle: String {
        switch self {
        case .release: localized("Release only")
        case .beta: localized("Beta only")
        case .all: localized("Beta and Release")
        }
    }

    fileprivate var lastAttemptKey: String {
        self == .release ? "updateLastAttempt" : "updateLastAttempt." + rawValue
    }
}

struct UpdateVersion: Comparable {
    private let components: [Int]
    let betaNumber: Int?

    init?(_ tag: String) {
        let beta = tag.wholeMatch(of: AppBuildInfo.betaVersion)
        let core = beta.map { String($0.1) } ?? tag
        let bare = core.first?.lowercased() == "v" ? core.dropFirst() : core[...]
        let parts = bare.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count),
            parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } })
        else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        components = numbers + Array(repeating: 0, count: 4 - numbers.count)

        if let beta {
            guard let number = Int(beta.2 ?? "0") else { return nil }
            betaNumber = number
        } else {
            betaNumber = nil
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.components != rhs.components { return lhs.components.lexicographicallyPrecedes(rhs.components) }
        switch (lhs.betaNumber, rhs.betaNumber) {
        case (.some(let lhs), .some(let rhs)): return lhs < rhs
        case (.some, .none): return true
        default: return false
        }
    }
}

/// Checks the selected channel. All request state is driven on the main queue.
final class UpdateChecker: ObservableObject {
    typealias Fetch = (URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void

    struct Release: Equatable {
        let version: String
        let page: URL
        fileprivate let order: UpdateVersion
    }

    enum State: Equatable {
        case idle, checking, upToDate, noEligibleRelease, awaitingStable, available(Release), failed
    }

    enum Failure: Error, Equatable {
        case transport(String)
        case rejected(status: Int)
        case malformed
    }

    /// The two fallback URLs accept GitHub's single-release and release-list responses respectively.
    static let backupAPI: URL? = nil
    static let backupReleasesAPI: URL? = nil

    private static let site = URL(string: "https://github.com/LShayc1owN/WhiskyMac/releases/tag")!
    private static let listAPI = URL(string: "https://api.github.com/repos/LShayc1owN/WhiskyMac/releases")!
    private static let latestAPI = listAPI.appendingPathComponent("latest")
    private static let channelKey = "updateChannel"
    private static let launchInterval: TimeInterval = 24 * 60 * 60

    @Published private(set) var channel: UpdateChannel
    @Published private(set) var state: State = .idle

    private let backup: URL?
    private let backupReleases: URL?
    private let defaults: UserDefaults
    private let now: () -> Date
    private let currentVersion: UpdateVersion?
    private let distribution: Distribution
    private let fetch: Fetch
    private let logger: any Logger
    private var activeCheck: UUID?

    var canCheckForUpdates: Bool { distribution.checksForUpdates && currentVersion != nil }

    var availableRelease: Release? {
        guard case .available(let release) = state else { return nil }
        return release
    }

    init(
        currentVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        fetch: @escaping Fetch = { url, completion in
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            URLSession.shared.dataTask(with: request, completionHandler: completion).resume()
        },
        logger: any Logger = ConsoleLogger(),
        backupAPI: URL? = UpdateChecker.backupAPI,
        backupReleasesAPI: URL? = UpdateChecker.backupReleasesAPI,
        defaults: UserDefaults = AppIdentity.defaults,
        now: @escaping () -> Date = Date.init,
        distribution: Distribution = .current
    ) {
        self.currentVersion = currentVersion.flatMap(UpdateVersion.init)
        self.fetch = fetch
        self.logger = logger
        backup = backupAPI?.scheme == "https" ? backupAPI : nil
        backupReleases = backupReleasesAPI?.scheme == "https" ? backupReleasesAPI : nil
        self.defaults = defaults
        self.now = now
        self.distribution = distribution
        channel = defaults.string(forKey: Self.channelKey).flatMap(UpdateChannel.init(rawValue:)) ?? .release
    }

    func setChannel(_ channel: UpdateChannel) {
        guard self.channel != channel else { return }
        activeCheck = nil
        state = .idle
        self.channel = channel
        defaults.set(channel.rawValue, forKey: Self.channelKey)
    }

    /// Manual checks bypass the launch interval; concurrent checks of the same channel are coalesced.
    func checkNow(automatic: Bool = false) {
        guard activeCheck == nil, canCheckForUpdates, let current = currentVersion else { return }
        let channel = self.channel
        let time = now()
        if automatic, let last = defaults.object(forKey: channel.lastAttemptKey) as? Date {
            let elapsed = time.timeIntervalSince(last)
            guard elapsed < 0 || elapsed >= Self.launchInterval else { return }
        }
        defaults.set(time, forKey: channel.lastAttemptKey)
        let check = Check(id: UUID(), channel: channel, current: current)
        activeCheck = check.id
        state = .checking
        request(
            check, from: channel == .release ? Self.latestAPI : Self.listAPI,
            fallback: channel == .release ? backup : backupReleases)
    }

    private struct Check {
        let id: UUID
        let channel: UpdateChannel
        let current: UpdateVersion
    }

    private func request(
        _ check: Check, from source: URL, fallback: URL?, page: Int = 1, best: Release? = nil
    ) {
        let url = check.channel == .release ? source : Self.listPage(source, page: page)
        fetch(url) { [weak self] data, response, error in
            let result = Self.readPage(data: data, response: response, error: error, channel: check.channel, page: page)
            DispatchQueue.main.async {
                guard let self, self.activeCheck == check.id else { return }
                switch result {
                case .failure(let failure):
                    if let fallback {
                        self.request(check, from: fallback, fallback: nil)
                    } else {
                        self.finish(.failed)
                        self.log(failure)
                    }
                case .success(let batch):
                    let candidate = Self.newerRelease(best, batch.best)
                    if let next = batch.nextPage {
                        self.request(check, from: source, fallback: fallback, page: next, best: candidate)
                    } else {
                        self.finish(Self.outcome(for: candidate, check: check))
                    }
                }
            }
        }
    }

    private func finish(_ state: State) {
        activeCheck = nil
        self.state = state
    }

    private func log(_ failure: Failure) {
        switch failure {
        case .transport: logger.log(.updateTransportFailed)
        case .rejected(let status): logger.log(.updateHTTPRejected, status: status)
        case .malformed: logger.log(.updateResponseInvalid)
        }
    }

    private static func outcome(for release: Release?, check: Check) -> State {
        guard let release else { return .noEligibleRelease }
        if release.order > check.current { return .available(release) }
        if check.channel == .release, check.current.betaNumber != nil, release.order < check.current {
            return .awaitingStable
        }
        return .upToDate
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let draft: Bool?
        let prerelease: Bool?

        func candidate(in channel: UpdateChannel) -> Release? {
            guard draft != true, let version = UpdateVersion(tag_name) else { return nil }
            let isBeta = version.betaNumber != nil
            guard (prerelease == true) == isBeta, channel != (isBeta ? .release : .beta) else { return nil }
            let display = tag_name.first?.lowercased() == "v" ? String(tag_name.dropFirst()) : tag_name
            return Release(version: display, page: UpdateChecker.site.appendingPathComponent(tag_name), order: version)
        }
    }

    /// Allow an invalid entry in a release list without discarding its valid neighbours.
    private struct ListEntry: Decodable {
        let release: GitHubRelease?
        init(from decoder: Decoder) { release = try? GitHubRelease(from: decoder) }
    }

    private struct ReleasePage {
        let best: Release?
        let nextPage: Int?
    }

    private static func readPage(
        data: Data?, response: URLResponse?, error: Error?, channel: UpdateChannel, page: Int
    ) -> Result<ReleasePage, Failure> {
        if let error { return .failure(.transport(error.localizedDescription)) }
        let http = response as? HTTPURLResponse
        if let http, !(200..<300).contains(http.statusCode) { return .failure(.rejected(status: http.statusCode)) }
        guard let data else { return .failure(.malformed) }
        let decoder = JSONDecoder()
        if channel == .release {
            guard let release = try? decoder.decode(GitHubRelease.self, from: data),
                let candidate = release.candidate(in: channel)
            else { return .failure(.malformed) }
            return .success(ReleasePage(best: candidate, nextPage: nil))
        }
        guard let entries = try? decoder.decode([ListEntry].self, from: data) else { return .failure(.malformed) }
        let best = entries.compactMap { $0.release?.candidate(in: channel) }.max { $0.order < $1.order }
        do {
            let next = try nextPage(in: http?.value(forHTTPHeaderField: "Link"), after: page)
            return .success(ReleasePage(best: best, nextPage: next))
        } catch {
            return .failure(.malformed)
        }
    }

    private static func newerRelease(_ first: Release?, _ second: Release?) -> Release? {
        guard let first else { return second }
        guard let second, first.order < second.order else { return first }
        return second
    }

    private static func listPage(_ source: URL, page: Int) -> URL {
        var components = URLComponents(url: source, resolvingAgainstBaseURL: false)
        var items = (components?.queryItems ?? []).filter { $0.name != "per_page" && $0.name != "page" }
        items += [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "page", value: String(page))]
        components?.queryItems = items
        return components?.url ?? source
    }

    /// Use only the next page number. The host and endpoint remain those of the configured source.
    private static func nextPage(in header: String?, after current: Int) throws -> Int? {
        guard let header else { return nil }
        for entry in header.split(separator: ",") {
            let parts = entry.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.dropFirst().contains(#"rel="next""#), let link = parts.first else { continue }
            guard current < 10, link.hasPrefix("<"), link.hasSuffix(">"),
                let components = URLComponents(string: String(link.dropFirst().dropLast())),
                let value = components.queryItems?.first(where: { $0.name == "page" })?.value,
                let next = Int(value), next == current + 1
            else { throw Failure.malformed }
            return next
        }
        return nil
    }
}
