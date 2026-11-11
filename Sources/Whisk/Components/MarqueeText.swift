// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// A single line that fades at the trailing edge when its text overflows.
struct MarqueeText: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let text: String
    let font: Font
    @State private var contentSize: CGSize = .zero

    init(_ text: String, font: Font) {
        self.text = text
        self.font = font
    }

    var body: some View {
        GeometryReader { geometry in
            Text(text.replacingOccurrences(of: "\n", with: " | "))
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .onGeometryChange(for: CGSize.self) {
                    $0.size
                } action: {
                    contentSize = $0
                }
                .frame(width: geometry.size.width, alignment: layoutDirection == .rightToLeft ? .trailing : .leading)
                .clipped()
                .mask {
                    if contentSize.width > geometry.size.width, geometry.size.width > 0 {
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0),
                                .init(color: .black, location: max(0, 1 - 16 / geometry.size.width)),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: layoutDirection == .rightToLeft ? .trailing : .leading,
                            endPoint: layoutDirection == .rightToLeft ? .leading : .trailing
                        )
                    } else {
                        Rectangle()
                    }
                }
        }
        .frame(height: max(1, contentSize.height))
        .accessibilityLabel(text)
    }
}
