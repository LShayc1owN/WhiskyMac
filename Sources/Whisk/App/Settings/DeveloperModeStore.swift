import Combine
import Foundation

/// The developer tools are always available in Debug builds. Other channels share the saved opt-in.
final class DeveloperModeStore: ObservableObject {
    private static let key = "developerModeEnabled"

    private let defaults: UserDefaults
    let canChange: Bool
    @Published private(set) var showsTools: Bool

    init(defaults: UserDefaults = AppIdentity.defaults, channel: AppBuildInfo.Channel = AppBuildInfo.current.channel) {
        self.defaults = defaults
        canChange = channel != .debug
        showsTools = channel == .debug || defaults.bool(forKey: Self.key)
    }

    func toggle() {
        guard canChange else { return }
        showsTools.toggle()
        defaults.set(showsTools, forKey: Self.key)
    }
}
