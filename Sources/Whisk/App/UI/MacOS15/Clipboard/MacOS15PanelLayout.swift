import CoreGraphics

/// Where the panel and its preview land on one screen. Pure geometry —
/// one rule for a 13-inch Air and an ultra-wide alike — so every display
/// shape can be checked without ordering a window in.
struct MacOS15PanelLayout: Equatable {
    /// One screen as AppKit reports it: the whole frame, what is left once
    /// the menu bar and the Dock are taken out, and the notch's height.
    typealias Screen = PanelLayout.Screen

    let panel: CGRect
    let preview: CGRect
    static let contentMargin: CGFloat = 16
    static let railVerticalPadding: CGFloat = 8
    static let contentSpacing: CGFloat = 6
    static let bottomPadding = contentMargin - railVerticalPadding

    // Leave room for the action row and two lines of the temporary preview.
    static func sensitiveRowHeight(_ typography: InterfaceTypography) -> CGFloat {
        24 + max(22, typography.lineHeight(13)) + 2 * typography.lineHeight(13)
    }

    /// Add the tag row's actual growth to the original panel chrome.
    static func panelHeight(
        forCardSide side: CGFloat, tagScale: Double = 1, typography: InterfaceTypography = .standard
    ) -> CGFloat {
        // Allow the search and action controls to grow without taking space from the card rail.
        let toolbarGrowth = typography.room(64) - 64
        let tags = MacOS15FilterTagMetrics(scale: tagScale, typography: typography)
        let tagGrowth = tags.totalRowHeight - (MacOS15FilterTagMetrics.originalRowHeight + 6)
        return (side + 230 + toolbarGrowth + tagGrowth).rounded(.up)
    }

    /// The panel's top band is empty backdrop, so the blur veil begins
    /// above the search capsule; a preview may lean into it when the
    /// screen is short.
    static let panelTopBand: CGFloat = 58

    static let previewSize = CGSize(width: 700, height: 480)
    /// Below this the preview stops shrinking: an unreadable preview
    /// helps nobody.
    static let previewMinimumHeight: CGFloat = 240
    /// Clearance between the panel's top edge and the preview.
    static let previewGap: CGFloat = 46
    /// Clearance between the preview and the menu bar, the notch or the
    /// screen's side edges.
    static let previewMargin: CGFloat = 16

    init(
        screen: Screen, cardSide: CGFloat, tagScale: Double = 1, typography: InterfaceTypography = .standard,
        showsSensitiveCopies: Bool = false
    ) {
        let frame = screen.frame
        let ceiling = min(screen.visibleFrame.maxY, frame.maxY - screen.notchHeight) - Self.previewMargin
        // The full frame, not visibleFrame: the panel floats above the
        // Dock, flush with the physical bottom edge of the screen. Oversized
        // cards scroll inside the panel instead of pushing its controls offscreen.
        let sensitiveHeight = showsSensitiveCopies ? Self.sensitiveRowHeight(typography) + Self.contentSpacing : 0
        panel = CGRect(
            x: frame.minX, y: frame.minY, width: frame.width,
            height: min(
                Self.panelHeight(forCardSide: cardSide, tagScale: tagScale, typography: typography) + sensitiveHeight,
                max(0, ceiling - frame.minY)))

        // The room is what lies between the panel and the menu bar — or
        // the notch, which a hidden menu bar leaves behind.
        let floor = panel.maxY + Self.previewGap
        let room = ceiling - floor

        let aspect = Self.previewSize.width / Self.previewSize.height
        var height = Self.previewSize.height
        let widest = frame.width - 2 * Self.previewMargin
        if height * aspect > widest {
            height = widest / aspect
        }
        if height > room {
            height = max(room, Self.previewMinimumHeight)
        }
        height.round(.down)
        let width = (height * aspect).rounded(.down)
        // Centered in the room, which reads the same on every screen. When
        // even the smallest preview does not fit, the menu bar wins and the
        // preview leans on the panel's empty band.
        let y = room >= height ? floor + (room - height) / 2 : ceiling - height
        preview = CGRect(x: (frame.midX - width / 2).rounded(), y: y.rounded(), width: width, height: height)
    }
    var result: PanelLayout { PanelLayout(panel: panel, preview: preview) }
}
