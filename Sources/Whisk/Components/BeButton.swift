// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

extension View {
    /// Makes this view the label of a button with an action.
    func beButton(_ action: @escaping () -> Void) -> Button<Self> {
        Button(action: action) { self }
    }

    /// Preserves a button role for labels with custom content.
    func beButton(role: ButtonRole, _ action: @escaping () -> Void) -> Button<Self> {
        Button(role: role, action: action) { self }
    }
}
