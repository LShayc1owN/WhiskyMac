// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import ImageIO

enum CardDragProvider {
    /// Cards can be dragged straight into other applications; the presenter
    /// decided what travels, this only wraps it for the drag session.
    static func make(for payload: DragPayload) -> NSItemProvider {
        switch payload {
        case .text(let value):
            return NSItemProvider(object: value as NSString)
        case .link(let url):
            return NSItemProvider(object: url as NSURL)
        case .storedImage(let reference):
            guard let data = try? reference.read() else { return NSItemProvider() }
            return make(for: .image(data))
        case .image(let data):
            guard
                let source = CGImageSourceCreateWithData(
                    data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                let type = CGImageSourceGetType(source)
            else { return NSItemProvider() }
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: type as String, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
            return provider
        case .files(let paths):
            // One provider per drag session: the first file travels.
            if let path = paths.first,
                let provider = NSItemProvider(contentsOf: URL(fileURLWithPath: path))
            {
                return provider
            }
            return NSItemProvider()
        }
    }

}
