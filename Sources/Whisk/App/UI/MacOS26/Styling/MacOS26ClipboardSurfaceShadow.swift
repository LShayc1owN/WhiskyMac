// WhiskyMac: modified or added 2026-11-19 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

@available(macOS 26, *)
extension View {
    /// Draw only the shadow behind the native material, keeping its backdrop live.
    func macOS26ClipboardShadow(in shape: some Shape, compact: Bool = false) -> some View {
        background {
            Canvas { context, size in
                let inset: CGFloat = compact ? 8 : 16
                context.addFilter(
                    .shadow(
                        color: .black.opacity(compact ? 0.18 : 0.24),
                        radius: compact ? 3 : 7, x: 0, y: compact ? 2 : 4,
                        options: .shadowOnly))
                context.fill(
                    shape.path(in: CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)),
                    with: .color(.black))
            }
            .padding(compact ? -8 : -16)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
