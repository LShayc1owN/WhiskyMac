import Testing

@testable import Whisk

@MainActor
@Suite struct DeveloperModeTests {
    @Test func debug_is_visible_and_beta_and_release_share_an_explicit_opt_in() throws {
        let sandbox = try IsolatedDefaults()
        let debug = DeveloperModeStore(defaults: sandbox.defaults, channel: .debug)
        debug.toggle()
        #expect(debug.showsTools && !debug.canChange)

        let beta = DeveloperModeStore(defaults: sandbox.defaults, channel: .beta)
        #expect(!beta.showsTools && beta.canChange)
        #expect(!DeveloperModeStore(defaults: sandbox.defaults, channel: .release).showsTools)

        beta.toggle()
        let release = DeveloperModeStore(defaults: sandbox.defaults, channel: .release)
        #expect(release.showsTools)
        release.toggle()
        #expect(!DeveloperModeStore(defaults: sandbox.defaults, channel: .beta).showsTools)
    }

    @Test func revocation_removes_the_tools_from_navigation_search_and_old_destinations() {
        let search = SettingsSearchModel()
        let requested = SettingsDestination(section: .debugging, anchor: "exportDiagnostics")
        let blindRequest = SettingsDestination(page: .debug, sectionIndex: 0)

        search.refresh(context: SettingsSearchContext(showsDeveloperTools: true))
        #expect(SettingsPage.visiblePages(showsDeveloperTools: true).contains(.debug))
        search.query = "Export logs"
        #expect(search.results.contains { $0.id == "exportDiagnostics" })
        search.activate("exportDiagnostics")
        #expect(search.destination == requested && search.highlightedAnchor == "exportDiagnostics")

        search.query = "Export logs"
        search.refresh(context: SettingsSearchContext(showsDeveloperTools: false))
        #expect(!SettingsPage.visiblePages(showsDeveloperTools: false).contains(.debug))
        #expect(!search.results.contains { $0.section == .debugging })
        #expect(search.destination == nil && search.highlightedAnchor == nil)

        let revision = search.navigationRevision
        search.activate("exportDiagnostics")
        search.activate("showWelcomeGuide")
        search.navigate(to: requested)
        search.navigate(to: blindRequest)
        #expect(search.navigationRevision == revision)
        #expect(search.destination == nil)
    }
}
