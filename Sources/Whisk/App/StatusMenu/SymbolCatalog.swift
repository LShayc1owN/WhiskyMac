import Foundation

enum SymbolCatalog {
    // Names only; artwork is supplied by the public NSImage symbol API.
    static let availableNames: [String] = {
        guard let url = AppResources.bundle.url(forResource: "SFSymbolNames", withExtension: "txt"),
            let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return AppSymbol.customNames }
        let versions: [String: String]
        if let metadata = AppResources.bundle.url(forResource: "SFSymbolAvailability", withExtension: "json"),
            let data = try? Data(contentsOf: metadata),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        {
            versions = decoded
        } else {
            versions = [:]
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return AppSymbol.customNames
            + contents.split(separator: "\n").map(String.init).filter { name in
                isAvailable(name, versions: versions, major: os.majorVersion, minor: os.minorVersion)
            }
    }()

    /// Availability metadata does not decode or cache thousands of vector images.
    static func isAvailable(_ name: String, versions: [String: String], major: Int, minor: Int) -> Bool {
        guard let version = versions[name] else { return true }
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard let required = parts.first else { return false }
        return major > required || (major == required && minor >= (parts.dropFirst().first ?? 0))
    }

    static func matching(_ names: [String], query: String) -> [String] {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "." })
        return names.filter { name in terms.allSatisfy { name.lowercased().contains($0) } }
    }
}
