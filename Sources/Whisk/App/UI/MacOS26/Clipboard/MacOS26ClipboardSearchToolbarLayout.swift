import AppKit
import SwiftUI

extension View {
    func macOS26ClipboardSearchPrompt(_ prompt: ClipboardSearchPrompt, accent: Color, isVisible: Bool) -> some View {
        // AppKit's SwiftUI text field bridge flattens styled placeholder text.
        ZStack(alignment: .leading) {
            if isVisible {
                Text(prompt.highlighted(accent: accent))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            self.accessibilityHint(prompt.label)
        }
    }
}

@available(macOS 26, *)
struct MacOS26ClipboardSearchMetrics {
    let preferredWidth: CGFloat
    let minimumWidth: CGFloat

    init(prompt: ClipboardSearchPrompt, expanded: Bool) {
        let promptWidth = prompt.width
        minimumWidth = promptWidth + 12
        preferredWidth = max(160, promptWidth + 72) + (expanded ? 80 : 0)
    }
}

/// Keeps the editable field mounted when localized controls need a second line.
@available(macOS 26, *)
struct MacOS26ClipboardSearchToolbarLayout: Layout {
    let field: MacOS26ClipboardSearchMetrics

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: proposal.width ?? .infinity, subviews: subviews)
        return frames.search.union(frames.actions).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(for: bounds.width, subviews: subviews)
        subviews[0].place(
            at: CGPoint(x: bounds.minX + frames.search.minX, y: bounds.minY + frames.search.minY),
            anchor: .topLeading, proposal: ProposedViewSize(frames.search.size))
        subviews[1].place(
            at: CGPoint(x: bounds.minX + frames.actions.minX, y: bounds.minY + frames.actions.minY),
            anchor: .topLeading, proposal: ProposedViewSize(frames.actions.size))
    }

    private func frames(for width: CGFloat, subviews: Subviews) -> (search: CGRect, actions: CGRect) {
        let preferredSearch = subviews[0].sizeThatFits(.unspecified)
        let actions = subviews[1].sizeThatFits(.unspecified)
        let gap: CGFloat = actions.width > 0 ? 10 : 0
        let minimumSearchWidth = preferredSearch.width - (field.preferredWidth - field.minimumWidth)
        let stacked = actions.width > 0 && width < minimumSearchWidth + gap + actions.width
        let availableSearch = stacked ? width : max(0, width - actions.width - gap)
        let searchWidth = min(preferredSearch.width, availableSearch)
        let searchHeight = subviews[0].sizeThatFits(ProposedViewSize(width: searchWidth, height: nil)).height
        if stacked {
            let rowWidth = max(searchWidth, actions.width)
            return (
                CGRect(x: (rowWidth - searchWidth) / 2, y: 0, width: searchWidth, height: searchHeight),
                CGRect(
                    x: (rowWidth - actions.width) / 2, y: searchHeight + MacOS26PanelLayout.contentSpacing,
                    width: actions.width, height: actions.height)
            )
        }
        let rowHeight = max(searchHeight, actions.height)
        return (
            CGRect(x: 0, y: (rowHeight - searchHeight) / 2, width: searchWidth, height: searchHeight),
            CGRect(
                x: searchWidth + gap, y: (rowHeight - actions.height) / 2,
                width: actions.width, height: actions.height)
        )
    }
}
