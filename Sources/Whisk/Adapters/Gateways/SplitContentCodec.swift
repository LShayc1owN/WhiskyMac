// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit

/// Local processing only; no link metadata, file previews or pasteboard reads.
enum SplitContentCodec {
    static func analyze(_ item: ClipboardItem, options: SplitOptions) throws -> [SplitCandidate] {
        try Task.checkCancellation()
        guard !item.pinnedMetadata.hidesContent, item.splitGroup == nil,
            let text = item.payload.transformableText
        else { throw SplitFailure.unavailable }
        guard text.utf16.count <= SplitLimits.maximumUTF16 else { throw SplitFailure.tooLarge }
        var attributed: NSAttributedString?
        if let data = item.rtf {
            if data.count <= SplitLimits.maximumRTFBytes,
                let decoded = try? NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
                decoded.string == text
            {
                attributed = decoded
            } else if !options.plainText {
                throw SplitFailure.richTextUnavailable
            }
        }
        let links = options.rule == .links ? try detectLinks(text, attributed: attributed) : []
        return try SplitText.candidates(text: text, options: options, links: links).map { candidate in
            try Task.checkCancellation()
            let part = candidate.part
            var rtf: Data?
            if !options.plainText, part.link == nil, let attributed {
                let selected = attributed.attributedSubstring(from: candidate.range)
                rtf = try selected.data(
                    from: NSRange(location: 0, length: selected.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            }
            return SplitCandidate(
                id: candidate.id, range: candidate.range,
                part: SplitPart(id: part.id, text: part.text, link: part.link, rtf: rtf))
        }
    }

    static func detectLinks(_ text: String, attributed: NSAttributedString?) throws -> [SplitLink] {
        var links: [SplitLink] = []
        func accepted(_ value: Any?) -> URL? {
            let url = (value as? URL) ?? (value as? String).flatMap(URL.init(string:))
            guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                return nil
            }
            return url
        }
        attributed?.enumerateAttribute(.link, in: NSRange(location: 0, length: attributed?.length ?? 0)) {
            value, range, _ in
            if let url = accepted(value) { links.append(SplitLink(range: range, url: url)) }
        }
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for match in detector.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)) {
            guard let url = accepted(match.url),
                !links.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 })
            else { continue }
            links.append(SplitLink(range: match.range, url: url))
        }
        return links.sorted { $0.range.location < $1.range.location }
    }

    static func combine(_ parts: [SplitPart], plainText: Bool) throws -> (Payload, Data?) {
        guard !parts.isEmpty else { throw SplitFailure.noSelection }
        if parts.count == 1 { return (parts[0].payload, plainText ? nil : parts[0].rtf) }
        let text = parts.map(\.text).joined(separator: "\n")
        if plainText { return (.text(text), nil) }
        let result = NSMutableAttributedString(string: "")
        for (index, part) in parts.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            if let data = part.rtf {
                guard
                    let decoded = try? NSAttributedString(
                        data: data,
                        options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
                    decoded.string == part.text
                else { throw SplitFailure.richTextUnavailable }
                result.append(decoded)
            } else {
                result.append(NSAttributedString(string: part.text, attributes: part.link.map { [.link: $0] } ?? [:]))
            }
        }
        let rtf = try result.data(
            from: NSRange(location: 0, length: result.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        return (.text(text), rtf)
    }
}
