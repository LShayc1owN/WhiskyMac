# LemonSlice custom SF Symbol

An original, complete circular lemon slice with six rounded pulp segments and a
separate rind. Transparent monochrome artwork; tint comes from the containing UI.

- `LemonSlice.xcassets/LemonSlice.symbolset/LemonSlice.svg`: importable SF Symbols
  template with nine weights and three scales, 27 explicit variants in total.
- `LemonSlice.svg`: standalone 24-unit SVG, Regular weight.
- `LemonSlice-preview.png`: light/dark, small-size, and weight previews.

The template uses Apple SF Symbols format 7.0 and requires Xcode 26 or later.
All symbol paths are closed filled outlines, without SVG strokes or raster data.
Baseline, cap-height, and per-variant margin guides are included. Seven rendering
layers and motion groups separate the rind from the six pulp segments. App
animations use `byLayer` to follow these groups.

Add the catalog to a target's compiled resources, or move `LemonSlice.symbolset`
into an existing asset catalog. Reference the symbol by asset name:

```swift
Image("LemonSlice")
    .renderingMode(.template)
    .font(.system(size: 15, weight: .regular))
    .imageScale(.medium)
```

For AppKit, load from the bundle owning the compiled catalog:

```swift
let image = NSImage(symbolName: "LemonSlice", bundle: bundle, variableValue: 0)?
    .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)
    )
image?.isTemplate = true
```

Validated with Xcode actool for macOS, deployment target 15.0, and actual AppKit
loading and rendering of all 27 weight/scale combinations. Regular/Medium at
15 pt produces a 16 x 16 pt image. The app compiles this catalog together with
WhiskyMac via `bash scripts/build-symbols.sh`, and uses LemonSlice as the default
Privacy Mode status icon. Both mode icons can be customized in Appearance settings.

Reference: [Apple - Creating custom symbols](https://developer.apple.com/documentation/technologyoverviews/custom-sf-symbols).
