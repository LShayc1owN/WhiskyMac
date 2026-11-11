// WhiskyMac: modified or added 2026-11-10 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Combine
import Foundation

extension SplitFailure {
    var message: String {
        switch self {
        case .unavailable: localized("Splitting is unavailable for this item.")
        case .stale: localized("The source changed or was removed. Reopen Split to continue.")
        case .tooLarge: localized("The source exceeds the split size limit.")
        case .tooManyParts: localized("More than 1000 results. Choose a different rule.")
        case .noDelimiter: localized("Select a delimiter or enter a custom separator.")
        case .invalidBoundary: localized("The separator cuts through a combined character. Choose another separator.")
        case .richTextUnavailable: localized("Rich text could not be preserved. Enable Plain text to continue.")
        case .noSelection: localized("Select at least one result.")
        case .capacity:
            localized(
                "The selected results do not fit the history capacity. Select fewer results or increase capacity.")
        case .needsEvictionConfirmation: localized("Confirm removal of older history before saving.")
        case .storage: localized("The results could not be saved. Your history and draft were kept.")
        }
    }
}

final class SplitSession: ObservableObject {
    @Published private(set) var source: ClipboardItem?
    @Published var options = SplitOptions() { didSet { if !resettingOptions, oldValue != options { analyze() } } }
    @Published var mode = SplitSaveMode.keepOriginal
    @Published var candidates: [SplitCandidate] = []
    @Published var confirmEviction = false
    @Published private(set) var evictedCount = 0
    @Published private(set) var error: String?
    @Published private(set) var analyzing = false
    private var resettingOptions = false
    private var assessmentFailed = false
    private var generation = 0
    private var task: Task<Void, Never>?
    private var worker: Task<[SplitCandidate], Error>?
    private let current: (UUID) -> ClipboardItem?
    private let allowed: () -> Bool
    private let assess: (SplitSaveRequest) throws -> SplitSaveAssessment
    private let save: (SplitSaveRequest, Bool) throws -> Void
    var completed: () -> Void = {}

    init(
        source: ClipboardItem, current: @escaping (UUID) -> ClipboardItem?, allowed: @escaping () -> Bool,
        assess: @escaping (SplitSaveRequest) throws -> SplitSaveAssessment,
        save: @escaping (SplitSaveRequest, Bool) throws -> Void
    ) {
        self.source = source; self.current = current; self.allowed = allowed; self.assess = assess; self.save = save
        analyze()
    }
    deinit { task?.cancel(); worker?.cancel() }

    var request: SplitSaveRequest? {
        guard let source else { return nil }
        return SplitSaveRequest(
            source: source, parts: candidates.filter(\.isSelected).map(\.part), mode: mode, plainText: options.plainText
        )
    }
    var canSave: Bool {
        source != nil && !analyzing && !assessmentFailed && candidates.contains(where: \.isSelected) && valid
    }
    private var valid: Bool {
        guard allowed(), let source else { return false }
        return current(source.id) == source && !source.pinnedMetadata.hidesContent && source.splitGroup == nil
    }

    func invalidateIfNeeded() { if !valid { invalidate() } }
    func invalidate() {
        generation += 1; task?.cancel(); worker?.cancel(); task = nil; worker = nil
        source = nil
        resettingOptions = true; options = SplitOptions(); resettingOptions = false
        candidates = []; analyzing = false; error = SplitFailure.stale.message
    }
    func analyze() {
        guard valid, let source else { invalidate(); return }
        generation += 1
        let token = generation
        task?.cancel(); worker?.cancel(); candidates = []; error = nil; analyzing = true; confirmEviction = false
        let options = options
        let worker = Task.detached(priority: .userInitiated) { try SplitContentCodec.analyze(source, options: options) }
        self.worker = worker
        task = Task { @MainActor [weak self] in
            let result = await worker.result
            guard let self, !Task.isCancelled, token == self.generation else { return }
            guard self.valid else { self.invalidate(); return }
            self.analyzing = false
            switch result {
            case .success(let candidates): self.candidates = candidates
            case .failure(let failure): self.error = (failure as? SplitFailure ?? .richTextUnavailable).message
            }
            self.refreshAssessment()
        }
    }
    func refreshAssessment() {
        evictedCount = 0; confirmEviction = false; assessmentFailed = false
        guard !analyzing, let request, !request.parts.isEmpty, valid else { return }
        do { evictedCount = try assess(request).evictedCount; error = nil } catch {
            assessmentFailed = true
            self.error = (error as? SplitFailure ?? .storage).message
        }
    }
    @discardableResult func commit() -> Bool {
        guard valid, canSave, let request else { invalidateIfNeeded(); return false }
        do {
            let currentCount = try assess(request).evictedCount
            if currentCount != evictedCount {
                evictedCount = currentCount; confirmEviction = false
                if currentCount > 0 { error = SplitFailure.needsEvictionConfirmation.message; return false }
            }
            try save(request, confirmEviction); completed(); return true
        } catch {
            self.error = (error as? SplitFailure ?? .storage).message; return false
        }
    }
}

final class SplitGroupSession: ObservableObject {
    @Published private(set) var source: ClipboardItem?
    @Published var selected: Set<UUID>
    @Published var original = false { didSet { if original { selected = [] } } }
    @Published private(set) var error: String?
    let action: CardAction
    let plain: Bool
    let query: String
    private let current: (UUID) -> ClipboardItem?
    private let allowed: () -> Bool
    private let export: (ClipboardItem, Set<UUID>, Bool, Bool, Bool) throws -> Void
    var completed: () -> Void = {}
    init(
        source: ClipboardItem, action: CardAction, plain: Bool, query: String,
        current: @escaping (UUID) -> ClipboardItem?, allowed: @escaping () -> Bool,
        export: @escaping (ClipboardItem, Set<UUID>, Bool, Bool, Bool) throws -> Void
    ) {
        self.source = source; self.action = action; self.plain = plain; self.query = query
        self.current = current; self.allowed = allowed; self.export = export
        selected = source.splitGroup?.parts.first.map { [$0.id] } ?? []
    }
    var valid: Bool {
        guard allowed(), let source else { return false }
        return current(source.id) == source && source.splitGroup != nil
    }
    func toggle(_ id: UUID, enabled: Bool) {
        original = false
        if enabled { selected.insert(id) } else { selected.remove(id) }
    }
    func matches(_ part: SplitPart) -> Bool {
        let words = ParsedQuery(query).words
        return !words.isEmpty && words.allSatisfy { FuzzyMatch.score(pattern: $0, in: part.text) != nil }
    }
    func invalidateIfNeeded() { if !valid { invalidate() } }
    func invalidate() { source = nil; selected = []; original = false; error = SplitFailure.stale.message }
    @discardableResult func commit() -> Bool {
        guard valid, let source else { invalidate(); return false }
        do {
            try export(source, selected, original, plain, action == .paste)
            completed(); return true
        } catch { self.error = (error as? SplitFailure ?? .storage).message; return false }
    }
}
