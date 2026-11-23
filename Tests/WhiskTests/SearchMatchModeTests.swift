import Foundation
import Testing

@testable import Whisk

@Suite struct SearchMatchModeTests {
    @Test func fuzzy_and_literal_modes_distinguish_subsequence_word_and_field_edges() {
        let start = anItem(.text("Alpha begins"))
        let middle = anItem(.text("a word: ALPHA!"))
        let end = anItem(.text("last alpha"))
        let inside = anItem(.text("alphabet soup"))
        let gapped = anItem(.text("a-l-p-h-a"))
        let history = History(items: [start, middle, end, inside, gapped])
        func results(_ mode: SearchMatchMode) -> [ClipboardItem] {
            FilterHistory()(history, filter: HistoryFilter(query: "alpha", searchMatchMode: mode))
        }
        #expect(Set(results(.fuzzy)) == Set(history.items))
        #expect(results(.containing) == [start, middle, end, inside])
        #expect(results(.matchingWord) == [start, middle, end])
        #expect(results(.startingWith) == [start, inside])
        #expect(results(.endingWith) == [end])
    }

    @Test func phrases_remain_literal_and_compose_with_query_operators_and_privacy_rules() {
        let target = anItem(.text("项目 a.*b  end"), from: "Editor", bundle: "test.editor", pinned: true)
        let hidden = target.withPinnedMetadata(PinnedMetadata(hidesContent: true))
        let wrongWidth = anItem(.text("项目 a.*b end"), from: "Editor", bundle: "test.editor", pinned: true)
        let wrongApp = anItem(.text("项目 a.*b  end"), from: "Terminal", bundle: "test.terminal", pinned: true)
        let filter = HistoryFilter(query: "app:editor type:text pinned A.*B  end", searchMatchMode: .endingWith)
        let search = FilterHistory()
        #expect(search(History(items: [target, wrongWidth, wrongApp]), filter: filter) == [target])
        #expect(search(History(items: [hidden]), filter: filter).isEmpty)
        #expect(
            search(History(items: [target]), filter: HistoryFilter(query: "pinned", searchMatchMode: .matchingWord))
                == [target])
    }

    @Test func highlighting_uses_the_same_utf16_ranges_and_does_not_invent_an_excerpt_boundary() {
        func spans(_ body: String, query: String, mode: SearchMatchMode) -> [MatchSpan] {
            let item = anItem(.text(body))
            let state = HistoryPresenter().present(
                items: [item], query: query, searchMatchMode: mode, now: item.copiedAt)
            return state.cards.first?.matches ?? []
        }
        #expect(spans("🚀 讨论 Café!", query: "CAFÉ", mode: .matchingWord) == [MatchSpan(start: 6, length: 4)])
        let excerpt = String(repeating: "x", count: 1018) + " alpha"
        #expect(spans(excerpt, query: "alpha", mode: .endingWith) == [MatchSpan(start: 1019, length: 5)])
        #expect(spans(excerpt + "more", query: "alpha", mode: .endingWith).isEmpty)
        #expect(spans(excerpt + "more", query: "alpha", mode: .matchingWord).isEmpty)
    }

    @MainActor
    @Test func selecting_a_mode_uses_the_current_query_and_rejects_stale_private_callbacks() {
        let scheduler = HandCrankedScheduler()
        let store = HistoryViewStateStore(
            protectedSearchDebounce: Debouncer(delay: 0.18, scheduler: scheduler.schedule))
        var changes: [(SearchMatchMode, String)] = []
        store.searchMatchModeChanged = { mode, query in changes.append((mode, query)) }
        store.setPanelVisible(true)
        store.selectSearchMatchMode(.containing, query: "latest typed text")
        #expect(changes.count == 1 && changes.last?.1 == "latest typed text")

        store.setPrivacy(true)
        store.selectSearchMatchMode(.matchingWord, query: "stale normal query")
        store.selectSearchMatchMode(.matchingWord, whileProtected: true)
        #expect(changes.count == 1)

        var searches: [String] = []
        store.protectedSearch = { searches.append($0) }
        store.setPrivacyPermissions(allowSearch: true, showSourceApps: false)
        store.searchWhileProtected("protected query")
        store.selectSearchMatchMode(.matchingWord, query: "ignored input", whileProtected: true)
        scheduler.fire()
        #expect(changes.count == 2 && changes.last?.0 == .matchingWord && changes.last?.1 == "protected query")
        #expect(searches.isEmpty)
        store.setPrivacyPermissions(allowSearch: false, showSourceApps: false)
        store.selectSearchMatchMode(.endingWith, whileProtected: true)
        #expect(changes.count == 2)
    }
}
