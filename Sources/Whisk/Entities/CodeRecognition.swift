// WhiskyMac: added 2026-11-25 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

/// Looks for syntax in a bounded excerpt. Runs when a history item is
/// created or loaded. Whitespace, punctuation and keywords alone are weak signals.
enum CodeRecognition {
    private static let scanLimit = 16 * 1024

    static func matches(_ text: String) -> Bool {
        let complete = text.utf8.count <= scanLimit
        let sample = complete ? text : String(decoding: text.utf8.prefix(scanLimit), as: UTF8.self)
        let range = NSRange(location: 0, length: sample.utf16.count)
        if patterns.contains(where: { $0?.firstMatch(in: sample, range: range) != nil }) { return true }

        // JSON is only treated as structured data when its root is a container
        // and the entire value parses. A scalar is often ordinary clipboard text.
        guard complete else { return false }
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
        else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }

    private static let identifier = #"[\p{L}_$][\w$]*"#
    private static let qualified = identifier + #"(?:[.:]"# + identifier + #")*"#
    private static let sqlFields = qualified + #"(?:[ \t]*,[ \t]*"# + qualified + #")*"#
    private static let modifiers =
        #"(?:(?:export|pub|public|private|protected|internal|final|static|async|override)[ \t]+)*"#
    private static let fenceLanguages =
        "swift|python|py|javascript|js|typescript|ts|json|rust|rs|go|java|kotlin|c|cpp|csharp|cs"
        + "|bash|sh|zsh|sql|html|xml|css|ruby|rb|php|lua|yaml|toml"

    private static func lines(_ patterns: [String], after modifiers: String = "") -> String {
        #"(?m)^[ \t]*"# + modifiers + "(?:" + patterns.joined(separator: "|") + ")"
    }

    // Match complete constructs or a characteristic statement opening.
    // Keeping these on line boundaries avoids counting punctuation inside prose.
    static let patterns: [NSRegularExpression?] = [
        // Declarations: language keywords followed by declaration syntax.
        lines(
            [
                #"(?:func|def|fn|function)[ \t]+"# + identifier + #"[ \t]*(?:<[^>\r\n]+>[ \t]*)?\("#,
                #"(?:let|var|const|val)[ \t]+"# + identifier + #"[ \t]*(?::[ \t]*"# + qualified + #"|=[ \t]*\S)"#,
                #"(?:class|struct|enum|interface|protocol|extension|impl)[ \t]+"#
                    + qualified + #"[ \t]*(?:[{<]|:[ \t]*"# + qualified + #"|extends\b|implements\b)"#,
                #"(?:void|int|double|float|char|bool|String)[ \t]+"# + identifier
                    + #"[ \t]*(?:\([^\r\n]*\)[ \t]*[{;]|=[ \t]*\S)"#,
            ], after: modifiers),
        // Module imports, preprocessors, and control-flow statements.
        lines([
            #"(?:from[ \t]+"# + qualified + #"[ \t]+)?import[ \t]+"# + qualified + #"(?:[ \t]+as[ \t]+"# + identifier
                + #")?[ \t]*;?$"#,
            #"(?:import[ \t]+(?:\{[^}\r\n]+\}|"# + identifier + #")[ \t]+from[ \t]+['"][^'"\r\n]+['"])[ \t]*;?$"#,
            #"#include[ \t]*[<"][\w./+-]+[>"][ \t]*$"#,
            #"(?:if|for|while|switch|catch)[ \t]*\([^\r\n]*\)[ \t]*\{"#,
            #"(?:if|elif|while)[ \t]+"# + identifier + #"[ \t]*:[ \t]*$"#,
            #"return[ \t]+(?:(?:true|false|nil|null|None)\b|[0-9"'\[(])"#,
        ]),
        // Calls and expressions with explicit structure. A lone name and a
        // parenthetical phrase is ambiguous, so bare calls need more evidence.
        lines([
            #"(?:await[ \t]+|try[!?]?[ \t]+)?"# + identifier + #"(?:\."# + identifier
                + #")+\([^\r\n]*\)[ \t]*;?[ \t]*$"#,
            #"(?:print|println|printf|assert|range|len)[ \t]*\([^\r\n]*\)[ \t]*;?[ \t]*$"#,
            identifier + #"[ \t]*\([ \t]*\)[ \t]*$"#,
            identifier + #"[ \t]*\([^\r\n]*\)[ \t]*;[ \t]*$"#,
            #"(?:"# + identifier + #"|\([^\r\n]*\))[ \t]*=>[ \t]*\S"#,
            identifier + #"(?:\."# + identifier + #")+[ \t]*\{[ \t]*\$[0-9]"#,
            identifier + #"[ \t]*=[ \t]*(?:(?:true|false|None|null|nil)|[-+]?[0-9]+(?:\.[0-9]+)?)[ \t]*;?$"#,
        ]),
        // Recognizable SQL and shell snippets. Ambiguous commands use an
        // option, a path, or a known complete subcommand as a signal.
        lines([
            #"(?i:select[ \t]+\*[ \t]+from[ \t]+)"# + qualified,
            #"SELECT[ \t]+"# + sqlFields + #"[ \t]+FROM[ \t]+"# + qualified + #"[ \t]*$"#,
            #"(?i:select[ \t]+"# + sqlFields + #"[ \t]+from[ \t]+"# + qualified
                + #"(?:[ \t]*;[ \t]*$|[ \t]+(?:where|join|limit|order[ \t]+by|group[ \t]+by)\b))"#,
            #"(?i:insert[ \t]+into)[ \t]+"# + qualified + #"[ \t]+(?i:values)[ \t]*\("#,
            #"(?i:update)[ \t]+"# + qualified + #"[ \t]+(?i:set)[ \t]+"# + identifier + #"[ \t]*="#,
            #"#!/[^\r\n]*(?:bash|zsh|sh|python[23]?|node)[ \t]*$"#,
            #"(?:\$[ \t]+)?git[ \t]+(?:status|diff|log)(?:[ \t]+--?[\w-]+)*[ \t]*$"#,
            #"(?:\$[ \t]+)?(?:ls|curl|grep|chmod|mkdir)[ \t]+--?[A-Za-z][^\r\n]*$"#,
            #"(?:\$[ \t]+)?echo[ \t]+(?:"[^\"\r\n]*"|'[^'\r\n]*')[ \t]*$"#,
            #"(?:\$[ \t]+)?cd[ \t]+(?:/|~/|\./|\.\./)[^\r\n]+$"#,
        ]),
        // Common markup, styles, and explicitly labelled Markdown code blocks.
        lines([#"[.#]?"# + identifier + #"[ \t]*\{\s*[-A-Za-z]+[ \t]*:[ \t]*[^;{}\r\n]+;"#]),
        #"\A\s*<(?:\?xml\s|!DOCTYPE\s+html\b)"#,
        #"\A\s*<([A-Za-z][\w:-]*)(?:\s+[^<>]*)?>(?s:.*?)</\1>\s*\z"#,
        #"\A\s*<[A-Za-z][\w:-]*(?:\s+[^<>]*)?/\s*>\s*\z"#,
        #"(?im)\A[ \t\r\n]*(```|~~~)(?:"# + fenceLanguages + #")[ \t]*\R[\s\S]+?^[ \t]*\1[ \t]*$"#,
    ].map { try? NSRegularExpression(pattern: $0) }
}
