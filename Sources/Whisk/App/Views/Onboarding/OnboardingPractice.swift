// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct OnboardingPractice: View {
    @ObservedObject var session: OnboardingPracticeSession
    @ObservedObject var general: GeneralSettingsStore
    @ObservedObject var bindings: KeyBindingsStore
    @FocusState private var focused: Bool

    var body: some View {
        OnboardingSurface {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(localized("Practice space"), systemImage: "cursorarrow.click")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if session.hasExample {
                        Button(localized("Start over")) { session.reset() }
                            .buttonStyle(OnboardingButtonStyle(treatment: .quiet))
                            .foregroundStyle(OnboardingStyle.green)
                            .font(.caption)
                    }
                }
                Text(
                    localized("Try it safely with sample content.")
                )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !session.hasExample {
                    HStack(spacing: 16) {
                        Image(systemName: "doc.text").font(.system(size: 25)).foregroundStyle(OnboardingStyle.green)
                        Text(session.text).font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Button(localized("Add example")) { session.addExample() }
                            .buttonStyle(OnboardingButtonStyle(treatment: .secondary))
                            .accessibilityIdentifier("onboarding.practice.add")
                    }
                    .padding(16).frame(minHeight: 90)
                    .background(OnboardingStyle.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    .transition(OnboardingMotion.enter(y: 4))
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 7) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField(localized("Try searching for Hello"), text: $session.query)
                                    .textFieldStyle(.plain).font(.caption)
                                    .onSubmit { focused = true }
                                    .accessibilityIdentifier("onboarding.practice.search")
                            }.padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                            if session.matches {
                                exampleCard.transition(.opacity)
                            } else {
                                Text(localized("No match. Try Hello or clear the search."))
                                    .font(.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 110)
                                    .transition(.opacity)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .animation(OnboardingMotion.press, value: session.matches)
                        Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                            .padding(.top, 65).accessibilityHidden(true)
                        practiceNote
                    }
                    .transition(OnboardingMotion.enter(y: 6))
                }
                if let presentation = session.presentation {
                    presentationView(presentation).transition(OnboardingMotion.enter(y: 4))
                }
                if let feedback = session.feedback {
                    Label(
                        feedbackText(feedback),
                        systemImage: session.isComplete ? "checkmark.circle.fill" : "info.circle"
                    )
                    .font(.caption).foregroundStyle(OnboardingStyle.green)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .transition(.opacity)
                    .accessibilityIdentifier("onboarding.practice.feedback")
                }
            }
            .animation(OnboardingMotion.detail, value: session.hasExample)
            .animation(OnboardingMotion.detail, value: session.presentation)
            .animation(OnboardingMotion.detail, value: session.feedback)
        }
        .background(
            OnboardingPracticeKeyMonitor(
                active: focused && session.canInteract && session.isSelected && session.presentation != .edit,
                bindings: bindings, perform: session.perform)
        )
        .onChange(of: general.interactions) { _, _ in session.cancelHover() }
        .onChange(of: bindings.recordingAction) { _, action in
            if action != nil { focused = false; session.cancelTransient() }
        }
        .onDisappear { session.cancelTransient() }
    }

    private var exampleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "text.alignleft").foregroundStyle(OnboardingStyle.green)
                Spacer()
                if session.isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(OnboardingStyle.green)
                        .accessibilityHidden(true)
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                Button {
                    run(.menu)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(OnboardingButtonStyle(treatment: .quiet)).help(localized("Example actions"))
                .accessibilityLabel(localized("Example actions"))
                .accessibilityIdentifier("onboarding.practice.menu")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(session.text).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(3)
                Text(
                    String(
                        format: localized("Single click: %@ · Double click: %@"),
                        general.interactions.singleClick.label, general.interactions.doubleClick.label)
                )
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(session.text)
            .accessibilityHint(
                String(
                    format: localized("Single click: %@ · Double click: %@"),
                    general.interactions.singleClick.label, general.interactions.doubleClick.label)
            )
            .accessibilityAction { run(general.interactions.singleClick) }
            .accessibilityIdentifier("onboarding.practice.select")
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingStyle.green.opacity(0.05), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11).strokeBorder(
                OnboardingStyle.green.opacity(session.isSelected ? 0.7 : 0.2))
        )
        .animation(OnboardingMotion.detail, value: session.isSelected)
        .gesture(
            TapGesture(count: 2).exclusively(before: TapGesture(count: 1)).onEnded { value in
                switch value {
                case .first: run(general.interactions.doubleClick)
                case .second: run(general.interactions.singleClick)
                }
            }
        )
        .background(CardRightClick { run(general.interactions.rightClick) })
        .onHover { inside in session.hover(inside: inside, interactions: general.interactions) }
        .focusable()
        .focused($focused)
    }

    private var practiceNote: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(localized("Practice note"), systemImage: "note.text").font(.caption).foregroundStyle(.secondary)
            Text(session.pastedText ?? localized("Your example lands here."))
                .font(.system(size: 12, design: .monospaced))
                .contentTransition(.opacity)
                .foregroundStyle(session.isComplete ? .primary : .tertiary)
                .frame(maxWidth: .infinity, minHeight: 75, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
            Button(localized("Paste example")) { run(.paste) }
                .buttonStyle(OnboardingButtonStyle(treatment: .secondary))
                .disabled(!session.isSelected || !session.canInteract)
                .accessibilityIdentifier("onboarding.practice.paste")
            OnboardingKeycap(text: bindings.label(for: .pasteSelection))
                .accessibilityLabel(bindings.label(for: .pasteSelection))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(
            session.isComplete ? OnboardingStyle.green.opacity(0.09) : OnboardingStyle.orange.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .animation(OnboardingMotion.detail, value: session.pastedText)
    }

    @ViewBuilder private func presentationView(_ presentation: OnboardingPracticeSession.Presentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(presentationTitle(presentation))
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.opacity)
                Spacer()
                Button {
                    session.dismissPresentation(); focused = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(OnboardingButtonStyle(treatment: .quiet)).accessibilityLabel(localized("Cancel"))
            }
            switch presentation {
            case .preview:
                Text(session.text).font(.system(size: 12, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
            case .edit:
                TextEditor(text: $session.draft).font(.system(size: 12, design: .monospaced))
                    .frame(height: 95)
                    .accessibilityLabel(localized("Edit example"))
                HStack {
                    Spacer()
                    Button(localized("Cancel")) {
                        session.dismissPresentation(); focused = true
                    }
                    Button(localized("Save")) {
                        session.saveEdit(); focused = true
                    }
                    .disabled(!session.canSaveEdit)
                }
            case .split:
                Text(localized("By line")).font(.caption).foregroundStyle(.secondary)
                ForEach(session.splitParts) { part in
                    HStack(alignment: .top) {
                        Text(String(part.id + 1)).foregroundStyle(OnboardingStyle.green).frame(width: 16)
                        Text(part.part.text).fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 12))
                }
                Text(localized("Split results are examples only and are not saved to history."))
                    .font(.caption).foregroundStyle(.secondary)
            case .menu:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 12
                ) {
                    ForEach([CardAction.preview, .copy, .paste, .edit, .split], id: \.rawValue) { action in
                        Button(action.label) { run(action) }
                            .buttonStyle(OnboardingButtonStyle(treatment: .secondary))
                    }
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(OnboardingStyle.green.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private func run(_ action: CardAction) {
        focused = true
        session.perform(action)
    }

    private func presentationTitle(_ presentation: OnboardingPracticeSession.Presentation) -> String {
        switch presentation {
        case .preview: localized("Preview")
        case .edit: localized("Edit example")
        case .split: localized("Split options")
        case .menu: localized("Example actions")
        }
    }

    private func feedbackText(_ feedback: OnboardingPracticeSession.Feedback) -> String {
        switch feedback {
        case .selected:
            localized(
                "Use the card menu or a shortcut to continue."
            )
        case .copied: localized("Sample copied.")
        case .pasted: localized("Sample pasted.")
        case .edited: localized("Sample updated.")
        case .splitFailed: localized("This example could not be split. Try a shorter text.")
        }
    }

}
