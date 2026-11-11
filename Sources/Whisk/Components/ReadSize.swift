// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

extension View {
    /// Reports the laid out size whenever it changes.
    func readSize(_ onChange: @escaping (CGSize) -> Void) -> some View {
        onGeometryChange(for: CGSize.self) { geometry in
            geometry.size
        } action: { size in
            onChange(size)
        }
    }
}
