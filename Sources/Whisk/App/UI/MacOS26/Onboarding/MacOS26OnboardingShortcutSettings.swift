// WhiskyMac: modified or added 2026-11-18 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

@available(macOS 26, *)
struct MacOS26OnboardingShortcutSettings: View {
    @Environment(\.interfaceTypography) private var typography
    @ObservedObject var bindings: KeyBindingsStore
    var includesPanelActions = false

    var body: some View {
        MacOS26OnboardingSurface {
            VStack(alignment: .leading, spacing: 10) {
                if includesPanelActions {
                    Label(localized("Keyboard shortcuts"), systemImage: "keyboard")
                        .font(typography.font(size: 16, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                Text(localized("Click the shortcut to change it. Press Esc to cancel."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(
                    localized("Enable the history shortcut"),
                    isOn: Binding(
                        get: { bindings.isGlobalEnabled(.togglePanel) },
                        set: { bindings.setGlobalEnabled($0, for: .togglePanel) })
                )
                .toggleStyle(.switch)
                shortcut(.togglePanel)
                if includesPanelActions {
                    Divider()
                    shortcut(.pasteSelection)
                    shortcut(.copySelection)
                }
                if hasShortcutConflict {
                    Label {
                        Text(localized("This shortcut is unavailable or duplicated. Choose another combination."))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }
                    .font(typography.font(.body).weight(.medium))
                }
            }
            .font(typography.font(size: 14))
        }
    }

    private var hasShortcutConflict: Bool {
        let duplicates = bindings.duplicatedActions
        return bindings.registrationFailures.contains(.togglePanel) || duplicates.contains(.togglePanel)
            || (includesPanelActions && (duplicates.contains(.pasteSelection) || duplicates.contains(.copySelection)))
    }

    private func shortcut(_ action: KeyAction) -> some View {
        HStack {
            Text(action.displayName).fixedSize(horizontal: false, vertical: true)
            Spacer()
            MacOS26OnboardingKeycap(
                text: bindings.recordingAction == action
                    ? localized("Press a shortcut…") : bindings.label(for: action),
                recording: bindings.recordingAction == action
            )
            .frame(minHeight: 32)
            .beButton {
                if bindings.recordingAction == action {
                    bindings.endRecording()
                } else {
                    bindings.beginRecording(action)
                }
            }
            .buttonStyle(MacOS26OnboardingButtonStyle(treatment: .quiet))
            .help(localized("Click to record a shortcut. Escape cancels."))
            .accessibilityLabel(action.displayName)
            .accessibilityValue(
                bindings.recordingAction == action ? localized("Press a shortcut…") : bindings.label(for: action)
            )
            .accessibilityIdentifier("onboarding.shortcut.\(action.rawValue)")
        }
    }
}
