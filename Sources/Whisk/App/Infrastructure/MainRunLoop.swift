// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Bridges synchronous Foundation callbacks whose delivery is bound to the main run loop.
@MainActor
enum MainRunLoop {
    static func observe(
        _ name: Notification.Name, in center: NotificationCenter = .default,
        perform: @escaping @MainActor (Notification) -> Void
    ) -> NSObjectProtocol {
        center.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { perform(note) }
        }
    }

    static func timer(
        interval: TimeInterval, repeats: Bool, perform: @escaping @MainActor () -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in
            MainActor.assumeIsolated { perform() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
