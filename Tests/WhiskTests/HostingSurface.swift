// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Inspect the actual host even when the factory wraps its root in a font environment.
@MainActor protocol TestHostingSurface: AnyObject {
    var sizingOptions: NSHostingSizingOptions { get }
    var renderedRoot: AnyView { get }
}

extension NSHostingView: TestHostingSurface {
    var renderedRoot: AnyView { AnyView(rootView) }
}
