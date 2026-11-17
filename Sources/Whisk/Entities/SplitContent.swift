// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

enum SplitRule: String, CaseIterable { case lines, paragraphs, delimiters, links }
enum SplitSaveMode: String, CaseIterable { case keepOriginal, replace, group }
enum SplitDelimiter: String, CaseIterable, Hashable {
    case comma, semicolon, enumeration, tab
    var values: [String] {
        switch self {
        case .comma: [",", "，"]
        case .semicolon: [";", "；"]
        case .enumeration: ["、"]
        case .tab: ["\t"]
        }
    }
}
struct SplitOptions: Equatable {
    var rule = SplitRule.lines
    var delimiters: Set<SplitDelimiter> = [.comma]
    var customDelimiter = ""
    var keepDelimiter = false
    var trimWhitespace = true
    var linksOnly = true
    var plainText = false
}

/// Only text and links are valid split parts; the group cannot nest or embed files.
struct SplitPart: Codable, Hashable, Identifiable {
    let id: UUID
    let text: String
    let link: URL?
    let richText: BinaryContent?
    var rtf: Data? { try? richText?.read() }

    init(id: UUID, text: String, link: URL?, rtf: Data?, richText: BinaryContent? = nil) {
        self.id = id; self.text = text; self.link = link
        self.richText = richText ?? rtf.map(BinaryContent.inline)
    }

    private enum CodingKeys: String, CodingKey { case id, text, link, rtf }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        link = try values.decodeIfPresent(URL.self, forKey: .link)
        richText = try values.decodeIfPresent(Data.self, forKey: .rtf).map(BinaryContent.inline)
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(text, forKey: .text)
        try values.encodeIfPresent(link, forKey: .link)
        try values.encodeIfPresent(richText?.read(), forKey: .rtf)
    }

    var payload: Payload { link.map(Payload.link) ?? .text(text) }
}
struct SplitGroup: Codable, Hashable {
    let parts: [SplitPart]
    let plainText: Bool
    func materialized() throws -> SplitGroup {
        SplitGroup(
            parts: try parts.map { SplitPart(id: $0.id, text: $0.text, link: $0.link, rtf: try $0.richText?.read()) },
            plainText: plainText)
    }

    var isValid: Bool {
        !parts.isEmpty && parts.count <= SplitLimits.maximumParts
            && Set(parts.map(\.id)).count == parts.count
            && parts.allSatisfy {
                !$0.text.isEmpty && ($0.link == nil || ["http", "https"].contains($0.link?.scheme?.lowercased() ?? ""))
            }
    }
}
struct SplitCandidate: Equatable, Identifiable {
    let id: Int
    let range: NSRange
    let part: SplitPart
    var isSelected = true
}
struct SplitLink: Equatable {
    let range: NSRange
    let url: URL
}
enum SplitLimits {
    static let maximumUTF16 = 1_000_000
    static let maximumParts = 1000
    static let maximumRTFBytes = 8 * 1024 * 1024
}
enum SplitFailure: Error, Equatable {
    case unavailable, stale, tooLarge, tooManyParts, noDelimiter, invalidBoundary, richTextUnavailable
    case noSelection, capacity, needsEvictionConfirmation, storage
}
