// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation

enum AppFilterTrigger: String, CaseIterable, Identifiable {
    case click, hover
    var id: String { rawValue }
    var label: String {
        switch self {
        case .click: localized("Click to filter")
        case .hover: localized("Hover to filter")
        }
    }
}

/// One cancellable dwell per mounted chip; stale callbacks cannot change filters.
final class FilterHoverActivation {
    static let delay: TimeInterval = 0.25
    private let scheduler: Debouncer.Scheduler
    private var work: DispatchWorkItem?
    private var generation = 0

    init(
        scheduler: @escaping Debouncer.Scheduler = { delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    ) { self.scheduler = scheduler }

    func enter(_ action: @escaping () -> Void) {
        cancel()
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, token == self.generation else { return }
            self.work = nil
            action()
        }
        self.work = work
        scheduler(Self.delay, work)
    }

    func cancel() {
        generation += 1
        work?.cancel()
        work = nil
    }

    deinit { work?.cancel() }
}
