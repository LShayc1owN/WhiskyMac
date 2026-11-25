// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing

@testable import Whisk

@Suite struct SpotlightExcerptTests {
    @Test func large_finder_copy_stops_at_the_visible_excerpt() {
        var visited = 0
        let names = (0..<20_000).lazy.map { i in
            visited += 1
            return "vector-\(i).svg"
        }
        let text = SpotlightExcerpt.fileList(names)
        #expect(text == String((0..<400).map { "vector-\($0).svg" }.joined(separator: "\n").prefix(4_000)))
        #expect(visited < 400)
    }

    @Test func paths_and_text_preserve_composed_characters_and_the_original_separator() {
        let names = ["abc\r", "a👩🏽‍💻e\u{301}", String(repeating: "👩🏽‍💻", count: 4_000), "hidden tail"]
        let expected = String(names.joined(separator: "\n").prefix(4_000))
        #expect(SpotlightExcerpt.fileList(names).utf8.elementsEqual(expected.utf8))
        #expect(SpotlightExcerpt(.text(names.joined(separator: "\n"))) == .text(expected))
        #expect(SpotlightExcerpt(.fileReferences(["/synthetic/a.pdf", "/else/b.svg"])) == .text("a.pdf\nb.svg"))
        #expect(
            SpotlightExcerpt(.fileReferences(["/synthetic/a.pdf", "/else/b.svg"]), includesFilePaths: true)
                == .text("/synthetic/a.pdf\n/else/b.svg"))
        #expect(SpotlightExcerpt(.fileReferences([])) == .text(""))
    }

    @Test func preparing_an_image_marker_does_not_load_original_bytes() {
        let ref = StoredBytes(
            key: "unused", byteCount: 99,
            read: {
                Issue.record("Unexpected original read"); return Data()
            }, matches: { _ in false })
        #expect(SpotlightExcerpt(.storedImage(ref)) == .image)
    }
}
