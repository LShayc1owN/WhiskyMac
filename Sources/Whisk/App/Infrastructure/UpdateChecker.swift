import Foundation

/// Checks the GitHub releases feed for a newer version. One anonymous
/// request at launch, nothing sent beyond it; DMG users get a menu entry,
/// Homebrew users already have `brew upgrade`.
final class UpdateChecker: ObservableObject {
    /// Performs the one request; URLSession in production, a canned reply
    /// in tests.
    typealias Fetch = (URL, @escaping (Data?, URLResponse?, Error?) -> Void) -> Void

    @Published private(set) var availableVersion: String?
    @Published private(set) var state: State = .idle

    enum State: Equatable {
        case idle, checking, upToDate, available(String), failed
    }

    /// Future server must return the same stable-release JSON schema as GitHub.
    /// Kept unset until an operator-controlled HTTPS endpoint is available.
    static let backupAPI: URL? = nil
    private let backup: URL?
    private let defaults: UserDefaults
    private let now: () -> Date
    private var checking = false

    /// Why a check yielded no version. Logged rather than swallowed: a
    /// rate-limited 403 would otherwise read exactly like "up to date".
    enum Failure: Error, Equatable {
        case transport(String)
        case rejected(status: Int)
        case malformed
    }

    static let releasesPage = URL(string: "https://github.com/LShayc1owN/WhiskyMac/releases/latest")

    private static let latestAPI = URL(
        string: "https://api.github.com/repos/LShayc1owN/WhiskyMac/releases/latest")

    private let currentVersion: String?
    private let fetch: Fetch
    private let logger: any Logger

    init(
        currentVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
        fetch: @escaping Fetch = { url, completion in
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            URLSession.shared.dataTask(with: request, completionHandler: completion).resume()
        },
        logger: any Logger = ConsoleLogger(),
        backupAPI: URL? = UpdateChecker.backupAPI,
        defaults: UserDefaults = AppIdentity.defaults,
        now: @escaping () -> Date = Date.init
    ) {
        self.currentVersion = currentVersion
        self.fetch = fetch
        self.logger = logger
        self.backup = backupAPI?.scheme == "https" ? backupAPI : nil
        self.defaults = defaults
        self.now = now
    }

    /// Manual checks bypass the launch interval; concurrent checks are coalesced.
    func checkNow(automatic: Bool = false) {
        guard !checking, let current = currentVersion, Self.versionParts(current) != nil,
            let url = Self.latestAPI
        else { return }
        if automatic, let last = defaults.object(forKey: "updateLastAttempt") as? Date,
            now().timeIntervalSince(last) < 24 * 60 * 60
        {
            return
        }
        defaults.set(now(), forKey: "updateLastAttempt")
        checking = true
        state = .checking
        request(url, current: current, mayFallback: true)
    }

    private func request(_ url: URL, current: String, mayFallback: Bool) {
        fetch(url) { [weak self] data, response, error in
            let result = Self.latestVersion(data: data, response: response, error: error)
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .failure(let failure):
                    if mayFallback, let backup = self.backup {
                        self.request(backup, current: current, mayFallback: false)
                        return
                    }
                    self.logger.log("update check failed — \(failure)")
                    self.state = .failed
                case .success(let latest):
                    self.availableVersion = Self.isNewer(latest, than: current) ? latest : nil
                    self.state = self.availableVersion.map(State.available) ?? .upToDate
                }
                self.checking = false
            }
        }
    }

    /// The latest published version in the releases API reply, or why
    /// there is none.
    static func latestVersion(data: Data?, response: URLResponse?, error: Error?) -> Result<String, Failure> {
        if let error {
            return .failure(.transport(error.localizedDescription))
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            return .failure(.rejected(status: http.statusCode))
        }
        guard let data,
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = payload["tag_name"] as? String,
            payload["draft"] as? Bool != true,
            payload["prerelease"] as? Bool != true,
            versionParts(tag) != nil
        else { return .failure(.malformed) }
        return .success(tag.hasPrefix("v") ? String(tag.dropFirst()) : tag)
    }

    private static func versionParts(_ value: String) -> [Int]? {
        let bare = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = bare.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 4,
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
            parts.allSatisfy({ Int($0) != nil })
        else { return nil }
        return parts.compactMap { Int($0) }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let lhs = versionParts(candidate), let rhs = versionParts(current) else { return false }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right {
                return left > right
            }
        }
        return false
    }
}
