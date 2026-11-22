// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct OnboardingPracticeSettings: View {
    @ObservedObject var session: OnboardingPracticeSession
    @ObservedObject var general: GeneralSettingsStore
    @ObservedObject var bindings: KeyBindingsStore

    var body: some View {
        OnboardingSurface {
            VStack(alignment: .leading, spacing: 14) {
                Label(localized("Clipboard controls"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                actionPicker(localized("Single click"), selection: $general.interactions.singleClick)
                actionPicker(localized("Double click"), selection: $general.interactions.doubleClick)
                Divider()
                shortcut(.pasteSelection)
                shortcut(.copySelection)
                if bindings.duplicatedActions.contains(.pasteSelection)
                    || bindings.duplicatedActions.contains(.copySelection)
                {
                    Label(
                        localized("This shortcut is unavailable or duplicated. Choose another combination."),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.orange)
                }
                DisclosureGroup(localized("More interactions"), isExpanded: $session.moreInteractions) {
                    VStack(alignment: .leading, spacing: 14) {
                        actionPicker(localized("Right click"), selection: $general.interactions.rightClick)
                        Picker(localized("Hover after a short delay"), selection: $general.interactions.hover) {
                            Text(CardAction.none.label).tag(CardAction.none)
                            Text(CardAction.preview.label).tag(CardAction.preview)
                        }
                        if general.interactions.hover == .preview {
                            HStack {
                                Text(localized("Hover delay (seconds)"))
                                Spacer()
                                TextField(
                                    "", value: $general.interactions.hoverDelay,
                                    format: .number.precision(.fractionLength(1))
                                )
                                .multilineTextAlignment(.trailing).frame(width: 50)
                                .accessibilityLabel(localized("Hover delay (seconds)"))
                                Stepper("", value: $general.interactions.hoverDelay, in: 0.1...5, step: 0.1)
                                    .labelsHidden().accessibilityLabel(localized("Hover delay (seconds)"))
                            }
                            .transition(OnboardingMotion.enter(y: 3))
                        }
                    }
                    .padding(.top, 12)
                    .animation(OnboardingMotion.detail, value: general.interactions.hover)
                }
                .animation(OnboardingMotion.detail, value: session.moreInteractions)
            }
            .font(.system(size: 12))
        }
    }

    private func actionPicker(_ title: String, selection: Binding<CardAction>) -> some View {
        Picker(title, selection: selection) {
            ForEach(CardAction.allCases, id: \.rawValue) { action in
                Text(action.label).tag(action)
            }
        }
    }

    private func shortcut(_ action: KeyAction) -> some View {
        HStack {
            Text(action.displayName)
            Spacer()
            Button {
                session.cancelTransient()
                if bindings.recordingAction == action {
                    bindings.endRecording()
                } else {
                    bindings.beginRecording(action)
                }
            } label: {
                OnboardingKeycap(
                    text: bindings.recordingAction == action
                        ? localized("Press a shortcut…") : bindings.label(for: action),
                    recording: bindings.recordingAction == action)
            }
            .buttonStyle(OnboardingButtonStyle(treatment: .quiet))
            .help(localized("Click to record a shortcut. Escape cancels."))
            .accessibilityLabel(action.displayName)
            .accessibilityValue(
                bindings.recordingAction == action ? localized("Press a shortcut…") : bindings.label(for: action)
            )
            .accessibilityIdentifier("onboarding.shortcut.\(action.rawValue)")
        }
    }
}
