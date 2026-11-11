// WhiskyMac: modified or added 2026-11-11 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import SwiftUI

struct ShortcutResetToast: View {
    @ObservedObject var undo: ShortcutResetUndo
    let accent: Color
    let onUndo: () -> Void
    @SettingsAccessibility private var accessibility

    var body: some View {
        HStack(spacing: 12) {
            Text(localized("Shortcuts reset"))
            Button(action: onUndo) {
                Label(localized("Undo reset"), systemImage: "arrow.uturn.backward")
                    .fontWeight(.semibold)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(accent.opacity(0.15), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .accessibilityHint(localized("Available for 5 seconds"))
        }
        .font(.callout)
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            if accessibility.reduceTransparency {
                Capsule().fill(Color(nsColor: .windowBackgroundColor))
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        .overlay {
            TimelineView(.animation(minimumInterval: accessibility.reduceMotion ? 1 : 1.0 / 30)) { _ in
                ResetToastBorder()
                    .trim(from: 0, to: undo.remainingFraction)
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

/// One continuous contour, starting at the top centre, for a clean perimeter countdown.
private struct ResetToastBorder: Shape {
    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: 1, dy: 1)
        let radius = min(bounds.width, bounds.height) / 2
        return Path { path in
            path.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
            path.addLine(to: CGPoint(x: bounds.maxX - radius, y: bounds.minY))
            path.addArc(
                center: CGPoint(x: bounds.maxX - radius, y: bounds.midY), radius: radius,
                startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: bounds.minX + radius, y: bounds.maxY))
            path.addArc(
                center: CGPoint(x: bounds.minX + radius, y: bounds.midY), radius: radius,
                startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
            path.closeSubpath()
        }
    }
}
