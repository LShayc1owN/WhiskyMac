import AppKit

enum SymbolCatalog {
    // Names only; artwork is supplied by the public NSImage symbol API.
    static let availableNames: [String] = {
        guard let url = AppResources.bundle.url(forResource: "SFSymbolNames", withExtension: "txt"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return AppSymbol.customNames }
        return AppSymbol.customNames
            + contents.split(separator: "\n").map(String.init).filter { name in
                autoreleasepool { NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil }
            }
    }()

    static func matching(_ names: [String], query: String) -> [String] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "." })
        return names.filter { name in terms.allSatisfy { name.lowercased().contains($0) } }
    }
}
