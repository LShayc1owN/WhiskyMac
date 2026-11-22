/// Diagnostic events carry no clipboard content or free-form error descriptions.
enum DiagnosticEvent: String, Codable, Sendable {
    case appStarted
    case historyLoadFailed
    case historyMutationFailed
    case historyRetentionFailed
    case pasteStackReadFailed
    case historyDirectoryUnavailable
    case historyDatabaseSetAside
    case historyDatabaseCreateFailed
    case legacyHistoryImportFailed
    case legacyHistoryRetireFailed
    case keyBindingsReadFailed
    case keyBindingsWriteFailed
    case excludedAppsReadFailed
    case excludedAppsWriteFailed
    case updateTransportFailed
    case updateHTTPRejected
    case updateResponseInvalid
    case cardExportFailed

    var category: String {
        switch self {
        case .appStarted: "lifecycle"
        case .keyBindingsReadFailed, .keyBindingsWriteFailed, .excludedAppsReadFailed, .excludedAppsWriteFailed:
            "settings"
        case .updateTransportFailed, .updateHTTPRejected, .updateResponseInvalid: "updates"
        case .cardExportFailed: "export"
        default: "storage"
        }
    }

    var level: String {
        switch self {
        case .appStarted: "INFO"
        case .historyDatabaseSetAside, .legacyHistoryRetireFailed, .keyBindingsReadFailed, .excludedAppsReadFailed:
            "WARNING"
        default: "ERROR"
        }
    }

    func safeStatus(_ status: Int?) -> Int? {
        guard self == .updateHTTPRejected, let status, (100...599).contains(status) else { return nil }
        return status
    }
}

protocol Logger {
    func log(_ event: DiagnosticEvent, status: Int?)
}

extension Logger {
    func log(_ event: DiagnosticEvent) { log(event, status: nil) }
}
