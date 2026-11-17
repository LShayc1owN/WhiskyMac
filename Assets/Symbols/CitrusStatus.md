# Citrus status symbols

Three original monochrome SF Symbols for the menu-bar icon picker:

| Asset name | Artwork |
| --- | --- |
| `LemonOpenSlice` | A lemon slice with a 60-degree opening centered toward the lower right (3:30 to 5:30) |
| `CitrusLeaf` | Two pointed leaves, a larger front leaf and a smaller rear leaf, with curved veins in negative space |
| `LemonLeaf` | The open slice partially covered by the same pair of leaves |

Each asset has a standalone 24-unit SVG and a matching `.xcassets` directory
containing its SF Symbols template. Each template supplies nine weights and
three scales as 27 explicit variants, with closed filled paths and baseline,
cap-height, and margin guides. Templates use format 7.0 (Xcode 26 or later).

Each visible part has a distinct rendering layer and motion group:

| Asset | Visible layers / motion groups |
| --- | --- |
| `LemonOpenSlice` | Rind and six individual pulp segments (7) |
| `CitrusLeaf` | Large leaf and small leaf (2) |
| `LemonLeaf` | Rind, six individual pulp segments, large leaf, small leaf (9) |

Each leaf can move independently. Transparent erase layers move with the leaf
they belong to, preserving overlap gaps while allowing the complete rear leaf
to emerge when the front leaf moves. The leaf veins remain part of their leaf;
the central gap between pulp segments is negative space, not an extra layer.
The opening spans 60 degrees; the remaining slice spans 300 degrees.
Use `.bounce.byLayer`, `.wiggle.byLayer`, or `.pulse.byLayer` for preset effects.
Draw On/Off guide points are not supplied.
The plain SVGs also name the visible parts using `rind`, `pulp1` through `pulp6`,
`large-leaf`, and `small-leaf` groups for editing. The annotated symbol-set SVG
is the file to import into SF Symbols or compile in Xcode.

The catalog build script compiles all three with the existing symbol resources:

```sh
bash scripts/build-symbols.sh
```

They appear in the app's menu-bar icon picker in Appearance settings. Existing
saved selections and default icons are preserved. Example within the app:

```swift
Image("LemonLeaf", bundle: AppSymbol.bundle)
    .symbolRenderingMode(.monochrome)
    .font(.system(size: 17, weight: .regular))
    .symbolEffect(.bounce.byLayer, value: trigger)
```

`CitrusStatus-preview.png` shows the three designs on light and dark backgrounds,
with small-size comparisons. Artwork is transparent and inherits its UI tint.
`CitrusLayers-preview.png` uses temporary debug colors to identify each visible
motion group, including the three groups in `LemonFruit`. The app's monochrome
assets retain their inherited tint. The compiled assets were loaded and rendered
with AppKit across all 108 weight/scale configurations for the four new symbols;
the existing status-symbol settings tests also pass.
