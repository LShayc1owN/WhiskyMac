// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Keeps each element's identity while also exposing its position to the row.
struct IndexedForEach<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
    let data: Data
    let id: KeyPath<Data.Element, ID>
    let content: (Data.Index, Data.Element) -> Content

    init(
        _ data: Data, id: KeyPath<Data.Element, ID>,
        @ViewBuilder content: @escaping (Data.Index, Data.Element) -> Content
    ) {
        self.data = data
        self.id = id
        self.content = content
    }

    var body: some View {
        let indexed = zip(data.indices, data).map { index, element in
            IndexedElement(index: index, element: element, id: element[keyPath: id])
        }
        ForEach(indexed) { entry in
            content(entry.index, entry.element)
        }
    }
}

extension IndexedForEach where Data.Element: Identifiable, ID == Data.Element.ID {
    init(_ data: Data, @ViewBuilder content: @escaping (Data.Index, Data.Element) -> Content) {
        self.init(data, id: \.id, content: content)
    }
}

private struct IndexedElement<Index, Element, ID: Hashable>: Identifiable {
    let index: Index
    let element: Element
    let id: ID
}
