import Foundation

/// Reports safe events to the unified log and to an optional app-owned store.
struct ConsoleLogger: Logger {
    var record: ((DiagnosticEvent, Int?) -> Void)? = nil

    func log(_ event: DiagnosticEvent, status: Int?) {
        let status = event.safeStatus(status)
        let detail = status.map { " status=\($0)" } ?? ""
        NSLog("WhiskyMac: [%@] [%@] %@%@", event.level, event.category, event.rawValue, detail)
        record?(event, status)
    }
}
