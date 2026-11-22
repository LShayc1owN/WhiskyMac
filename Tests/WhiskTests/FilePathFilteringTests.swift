// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation
import Testing

@testable import Whisk

@MainActor
@Suite struct FilePathFiltering {
    @Test(arguments: [
        "/Users/Example/Desktop/个人项目/学校/26大一期末小组作业/Demo数据/课表",
        "/tmp/a file.txt", "/Volumes/外接磁盘/资料/", "/", "~/Documents/笔记.md",
        "./资料/课程表", "../Demo数据/课表", "  /tmp/sample.txt\r\n",
        "\"/tmp/a file.txt\"", "'/tmp/a file.txt'", "/tmp/cafe\u{301}/🗂️",
        "/a/nonexistent/path/never-check-existence", "/tmp/let var && files.txt",
    ])
    func recognizes_single_paths_without_modifying_the_text(_ text: String) {
        let item = anItem(.text(text))
        #expect(item.category == .path)
        #expect(item.payload == .text(text))
    }

    @Test(arguments: [
        "", " ", "\"", "'", "plain text", "Documents/notes.txt", "Read /tmp/notes.txt",
        "https://example.com/a/b", "file:///tmp/notes.txt", "C:\\Users\\Example\\notes.txt",
        "/tmp/first\n/tmp/second", "/tmp/first\r/tmp/second", "/tmp/first\u{2028}second",
        "/tmp/nul\0file", "// a comment", "/* a comment */", "\"/tmp/unclosed",
    ])
    func unrelated_or_multiline_text_does_not_become_a_path(_ text: String) {
        #expect(Payload.text(text).category != .path)
    }

    @Test func filters_and_search_distinguish_path_text_from_files_links_and_prose() throws {
        let path = anItem(.text("/tmp/课表"), from: "Editor", bundle: "test.editor")
        let file = anItem(.fileReferences(["/tmp/课表"]))
        let link = anItem(.link(try #require(URL(string: "https://example.com/课表"))))
        let text = anItem(.text("See /tmp/课表 for details"))
        let history = History(items: [path, file, link, text])
        let filter = FilterHistory()
        #expect(filter(history, filter: HistoryFilter(categories: [.path])) == [path])
        #expect(filter(history, filter: HistoryFilter(query: "type:path")) == [path])
        #expect(filter(history, filter: HistoryFilter(query: "kind:path app:editor 课表")) == [path])
        #expect(filter(history, filter: HistoryFilter(categories: [.files])) == [file])
        let state = HistoryPresenter().present(
            items: [path], query: "", now: Date(),
            filters: FilterContext(chips: ChipEntry.row(hasPinned: false, sources: [], categories: [.path])))
        #expect(state.cards.first?.preview == .text("/tmp/课表"))
        #expect(state.cards.first?.kindSymbol == ContentCategory.path.symbolName)
        #expect(state.filters.kinds.first?.id == "path")
        #expect(state.filters.kinds.first?.label == localized("path").capitalized)
    }

    @Test func existing_text_storage_reclassifies_on_load_without_changing_payload_or_rtf() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipboardItem(
            id: UUID(), payload: .text("/tmp/never-open-this/课表"), source: nil,
            copiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            isPinned: false, rtf: Data([1, 2, 3]))
        try HistoryStorage.open(in: directory, log: { _ in }).save([item])
        let reopened = try HistoryStorage.open(in: directory, log: { _ in }).load()
        #expect(reopened == [item])
        #expect(reopened.first?.category == .path)
        #expect(reopened.first?.rtf == item.rtf)
    }

    @Test func controller_publishes_path_chip_and_privacy_type_filter_keeps_content_masked() {
        let state = HistoryViewStateStore()
        let disk = InMemoryHistoryStore()
        let board = ScriptedPasteboard()
        let path = anItem(.text("/tmp/PRIVATE_PATH"))
        disk.stored = [path, anItem(.text("ordinary text"))]
        let controller = ClipboardController(
            pasteboard: board, store: disk, clock: FakeClock(), present: { state.update($0) })
        #expect(state.state.filters.kinds.contains { $0.id == "path" })
        state.protectedFilter = { action in
            if case .toggleKind(let id) = action { controller.toggleCategoryFilter(id) }
            if case .reset = action { controller.toggleCategoryFilter(allFiltersChipID) }
        }
        state.setPrivacy(true)
        state.setPrivacyPermissions(allowSearch: false, showSourceApps: false, allowFiltering: true)
        state.setPanelVisible(true)
        state.filterWhileProtected(.toggleKind("path"))
        #expect(state.protectedCardIDs == [path.id])
        #expect(state.state == .empty && state.previewItems.isEmpty)
        #expect(board.written.isEmpty && disk.saveCount == 0)
    }
}
