// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation
import Testing

@testable import Whisk

@Suite struct LocalizationCatalogs {
    private static let languages = ["en", "fr", "de", "zh-Hans"]

    private struct StringCatalog: Decodable {
        struct Unit: Decodable {
            let state: String
            let value: String
        }

        struct Translation: Decodable {
            struct Variations: Decodable {
                let plural: [String: Translation]
            }

            let stringUnit: Unit?
            let variations: Variations?

            var units: [Unit] {
                if let stringUnit { return [stringUnit] }
                return variations?.plural.values.flatMap(\.units) ?? []
            }
        }

        struct Entry: Decodable {
            let extractionState: String
            let localizations: [String: Translation]
        }

        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func sourceCatalog() throws -> StringCatalog {
        let url = root.appendingPathComponent("Sources/Whisk/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: url))
    }

    private func catalog(_ language: String) throws -> [String: Any] {
        var merged: [String: Any] = [:]
        for ext in ["strings", "stringsdict"] {
            guard
                let url = Bundle.module.url(
                    forResource: "Localizable", withExtension: ext, subdirectory: nil, localization: language)
            else { continue }
            let dictionary = try #require(NSDictionary(contentsOf: url) as? [String: Any])
            merged.merge(dictionary) { current, _ in current }
        }
        return merged
    }

    /// Every key the sources ask for, each as the set of catalog keys it
    /// may resolve to: `"\(count) items"` reaches the catalog as
    /// `%lld items`, an object interpolation as `%@`.
    private func keysUsedInSources() throws -> [Set<String>] {
        let sources = root.appendingPathComponent("Sources/Whisk", isDirectory: true)
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let call = try NSRegularExpression(pattern: #"localized\(\s*"((?:[^"\\]|\\.)*)"\s*\)"#)
        let interpolation = try NSRegularExpression(pattern: #"\\\([^)]*\)"#)
        var used: [Set<String>] = []
        for case let file as URL in enumerator where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in call.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let literal = String(text[range]).replacingOccurrences(of: "\\\"", with: "\"")
                let whole = NSRange(literal.startIndex..., in: literal)
                used.append([
                    interpolation.stringByReplacingMatches(in: literal, range: whole, withTemplate: "%lld"),
                    interpolation.stringByReplacingMatches(in: literal, range: whole, withTemplate: "%@"),
                ])
            }
        }
        return used
    }

    @Test func every_language_ships_all_catalog_keys_and_translated_values() throws {
        let source = try sourceCatalog()
        #expect(source.sourceLanguage == "en")
        for language in Self.languages {
            let compiled = try catalog(language)
            #expect(Set(compiled.keys) == Set(source.strings.keys), "compiled keys for \(language)")
            let resource = try #require(
                Bundle.module.url(
                    forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
            let bundle = try #require(Bundle(url: resource.deletingLastPathComponent()))
            for (key, entry) in source.strings {
                #expect(entry.extractionState == "manual")
                #expect(Set(entry.localizations.keys) == Set(Self.languages))
                let translation = try #require(entry.localizations[language])
                #expect(!translation.units.isEmpty, "missing translation: \(language): \(key)")
                for unit in translation.units {
                    #expect(unit.state == "translated")
                    #expect(!unit.value.isEmpty)
                    #expect(try placeholders(in: unit.value) == placeholders(in: key), "\(language): \(key)")
                }
                if let unit = translation.stringUnit {
                    #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == unit.value)
                } else {
                    let categories = Set(translation.variations?.plural.keys.map { $0 } ?? [])
                    #expect(categories == (language == "zh-Hans" ? ["other"] : ["one", "other"]))
                }
            }
        }
    }

    private func placeholders(in text: String) throws -> [String] {
        let pattern = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|@)"#)
        return pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range, in: text) else { return nil }
            return String(text[range]).replacingOccurrences(of: #"^%\d+\$"#, with: "%", options: .regularExpression)
        }.sorted()
    }

    @Test func every_key_the_code_asks_for_exists() throws {
        let english = Set(try sourceCatalog().strings.keys)

        let missing = try keysUsedInSources().filter { $0.isDisjoint(with: english) }

        #expect(missing.isEmpty, "keys without a catalog entry: \(missing)")
    }

    @Test func no_catalog_key_lingers_unused() throws {
        let english = Set(try sourceCatalog().strings.keys)
        let used = try keysUsedInSources().reduce(into: Set<String>()) { $0.formUnion($1) }

        let unused = english.subtracting(used)

        #expect(unused.isEmpty, "catalog keys no code asks for: \(unused.sorted())")
    }

    @Test func strings_resolve_through_the_module_catalogs() throws {
        let values = try Self.languages.map { try #require(try catalog($0)["Forever"] as? String) }
        #expect(values.contains(localized("Forever")))
    }

    @Test func plural_forms_follow_the_count() {
        #expect(["1 item", "1 élément", "1 Eintrag", "1 项"].contains(localized("\(1) items")))
        #expect(["2 items", "2 éléments", "2 Einträge", "2 项"].contains(localized("\(2) items")))
        #expect(["1 character", "1 caractère", "1 Zeichen", "1 个字符"].contains(localized("\(1) characters")))
        #expect(["40 characters", "40 caractères", "40 Zeichen", "40 个字符"].contains(localized("\(40) characters")))
    }

    @Test(arguments: [0, 1, 2, 40])
    func plural_rules_follow_each_translation_independently_of_system_region(count: Int) throws {
        for language in Self.languages {
            let resource = try #require(
                Bundle.module.url(
                    forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: language))
            let bundle = try #require(Bundle(url: resource.deletingLastPathComponent()))
            let expected: [String]
            switch language {
            case "zh-Hans": expected = ["\(count) 项", "\(count) 个字符", "粘贴队列中有 \(count) 张卡片"]
            case "de":
                expected = [
                    "\(count) Eintr\(count == 1 ? "ag" : "äge")", "\(count) Zeichen",
                    "\(count) Karte\(count == 1 ? "" : "n") in der Einfügefolge",
                ]
            case "fr":
                let plural = count > 1 ? "s" : ""
                expected = [
                    "\(count) élément\(plural)", "\(count) caractère\(plural)",
                    "\(count) carte\(plural) dans la pile de collage",
                ]
            default:
                let plural = count == 1 ? "" : "s"
                expected = [
                    "\(count) item\(plural)", "\(count) character\(plural)",
                    "\(count) card\(plural) in the paste stack",
                ]
            }
            #expect(localized("\(count) items", bundle: bundle) == expected[0])
            #expect(localized("\(count) characters", bundle: bundle) == expected[1])
            #expect(localized("\(count) in the paste stack", bundle: bundle) == expected[2])
        }
    }

    @Test func language_preferences_select_chinese_and_fall_back_to_english() {
        let languages = AppResources.bundle.localizations
        #expect(
            Bundle.preferredLocalizations(from: languages, forPreferences: ["zh-Hans-CN", "en"])
                .map { $0.lowercased() } == ["zh-hans"])
        #expect(Bundle.preferredLocalizations(from: languages, forPreferences: ["fr", "en"]) == ["fr"])
        #expect(Bundle.preferredLocalizations(from: languages, forPreferences: ["de-DE", "en"]) == ["de"])
        #expect(Bundle.preferredLocalizations(from: languages, forPreferences: ["es", "en"]) == ["en"])
    }
}
