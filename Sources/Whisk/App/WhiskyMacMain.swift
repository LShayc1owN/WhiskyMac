import AppKit

@main
enum WhiskyMacMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate(uiFactory: AppUISelector.make())
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
