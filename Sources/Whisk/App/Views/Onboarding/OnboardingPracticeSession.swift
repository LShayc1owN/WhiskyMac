// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Combine
import Foundation

/// An example-only workspace with no pasteboard, history or system-action ports.
final class OnboardingPracticeSession: ObservableObject {
    enum Presentation { case preview, edit, split, menu }
    enum Feedback { case selected, copied, pasted, edited, splitFailed }

    @Published private(set) var hasExample = false
    @Published private(set) var isSelected = false
    @Published private(set) var text: String
    @Published private(set) var copiedText: String?
    @Published private(set) var pastedText: String?
    @Published private(set) var presentation: Presentation?
    @Published private(set) var feedback: Feedback?
    @Published private(set) var splitParts: [SplitCandidate] = []
    @Published var query = "" {
        didSet { if !matches { cancelTransient() } }
    }
    @Published var draft = ""
    @Published var moreInteractions = false

    private let sample: String
    private var hoverTask: Task<Void, Never>?
    private var hoverRevision = 0
    private var hoverPreview = false
    private let sleep: (Double) async throws -> Void

    init(
        sample: String = localized("Hello, WhiskyMac.\nA good idea.\nReady when you are."),
        sleep: @escaping (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.sample = sample
        text = sample
        self.sleep = sleep
    }

    deinit { hoverTask?.cancel() }

    var matches: Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
    var canInteract: Bool { hasExample && matches }
    var isComplete: Bool { pastedText != nil }
    var canSaveEdit: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func addExample() {
        guard !hasExample else { return }
        hasExample = true
    }

    func perform(_ action: CardAction) {
        guard canInteract else { return }
        cancelHover()
        hoverPreview = false
        isSelected = true
        presentation = nil
        switch action {
        case .none: feedback = .selected
        case .copy:
            copiedText = text
            feedback = .copied
        case .paste:
            copiedText = text
            pastedText = text
            feedback = .pasted
        case .preview: presentation = .preview
        case .menu: presentation = .menu
        case .edit:
            draft = text
            presentation = .edit
        case .split:
            do {
                splitParts = try SplitText.candidates(text: text, options: SplitOptions())
                presentation = .split
            } catch {
                splitParts = []
                feedback = .splitFailed
            }
        }
    }

    func saveEdit() {
        guard presentation == .edit, canSaveEdit else { return }
        text = draft
        presentation = nil
        feedback = .edited
    }

    func dismissPresentation() {
        cancelHover()
        presentation = nil
        hoverPreview = false
        draft = ""
    }

    @discardableResult
    func hover(inside: Bool, interactions: InteractionBindings) -> Task<Void, Never>? {
        cancelHover()
        guard inside, canInteract, interactions.hover == .preview, presentation == nil else { return nil }
        let revision = hoverRevision
        let delay = interactions.hoverDelay
        let sleep = sleep
        hoverTask = Task { @MainActor [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled, let self, revision == self.hoverRevision, self.canInteract,
                self.presentation == nil
            else { return }
            self.isSelected = true
            self.presentation = .preview
            self.hoverPreview = true
        }
        return hoverTask
    }

    func cancelHover() {
        hoverRevision += 1
        hoverTask?.cancel()
        hoverTask = nil
        if hoverPreview {
            presentation = nil
            hoverPreview = false
        }
    }

    func cancelTransient() {
        dismissPresentation()
    }

    func reset() {
        cancelTransient()
        hasExample = false
        isSelected = false
        text = sample
        copiedText = nil
        pastedText = nil
        query = ""
        draft = ""
        feedback = nil
        splitParts = []
    }
}
