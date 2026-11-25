// WhiskyMac: modified or added 2026-11-15 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import Foundation
import ImageIO

enum ImageThumbnailDecoder {
    static let maximumPixelSize = 2048

    static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(
            source, 0,
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(maximumPixelSize, max(1, maxPixelSize)),
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
    }
}
