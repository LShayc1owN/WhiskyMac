// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import SwiftUI

struct SettingsAccessibilityValues {
    var reduceMotion = false
    var reduceTransparency = false
    var increasedContrast = false
}

private struct SettingsAccessibilityOverrideKey: EnvironmentKey {
    static let defaultValue: SettingsAccessibilityValues? = nil
}

extension EnvironmentValues {
    var settingsAccessibilityOverride: SettingsAccessibilityValues? {
        get { self[SettingsAccessibilityOverrideKey.self] }
        set { self[SettingsAccessibilityOverrideKey.self] = newValue }
    }
}

@propertyWrapper
struct SettingsAccessibility: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.settingsAccessibilityOverride) private var override

    var wrappedValue: SettingsAccessibilityValues {
        override
            ?? SettingsAccessibilityValues(
                reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                increasedContrast: contrast == .increased)
    }
}
