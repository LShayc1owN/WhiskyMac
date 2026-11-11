# WhiskyMac custom SF Symbol

Original monochrome vector artwork based on the approved WhiskyMac app icon:
a triangular stemmed glass, a complete citrus slice, a thin foam band in negative
space, and two aroma curves. The citrus has six simplified segments for clarity
at small sizes.

## Deliverables

- `WhiskyMac.xcassets/WhiskyMac.symbolset/WhiskyMac.svg`: the importable Apple
  SF Symbols template, with 27 explicitly drawn variants (nine weights, S/M/L),
  outlined filled paths, and baseline, cap-height, and per-variant margin guides.
- `WhiskyMac.svg`: a plain 24-unit SVG of the Regular artwork, for vector editors
  and general-purpose rendering. This file is not the SF Symbols template.
- `WhiskyMac-preview.png`: light/dark previews, small sizes, and weight comparisons.
- `WhiskyMac-layers.png`: native palette rendering that identifies the three layers.

The symbol template uses format 7.0 from the installed Apple SF Symbols tool.
Use Xcode 26 or later to compile the asset catalog. The symbol is monochrome;
color comes from the containing UI. All 27 weight/scale variants are explicitly
drawn and include rendering-layer and motion-group annotations.

## Animation layers

The five original paths form three rendering layers and three motion groups:

| Layer | Contents | Motion group | Hierarchy |
| --- | --- | --- | --- |
| Glass | Bowl, stem, base, and liquid | 0 | Primary |
| Lemon | Complete lemon slice | 1 | Secondary |
| Aroma | Both aroma curves together | 2 | Tertiary |

Monochrome geometry is unchanged. The glass and liquid always move together,
as do the two aroma curves. Each group is enabled for Pulse; Bounce uses the
three motion groups. Palette mode can assign a different color to each layer.
The plain SVG also exposes `glass`, `lemon`, and `aroma` groups for vector editors.

For a SwiftUI view inside this app, use the owning symbol bundle and trigger a
layered bounce by changing `animationTrigger`:

```swift
Image("WhiskyMac", bundle: AppSymbol.bundle)
    .symbolRenderingMode(.monochrome)
    .symbolEffect(.bounce.byLayer, value: animationTrigger)
```

For a repeating pulse, use `.symbolEffect(.pulse.byLayer, isActive: isPulsing)`.
These are SF Symbols preset animations: `byLayer` follows the annotated groups;
it does not expose arbitrary per-layer transforms in SwiftUI. Draw On/Off needs
additional path guide-point annotations in the SF Symbols app, which this file
does not provide. Keep the annotations by using **Export Symbol** when exporting
from SF Symbols; **Export Template** is intended for vector editing.

## Use

Add `WhiskyMac.xcassets` to an app target's resources, or move the symbol set into
an existing asset catalog. Reference it by its asset name `WhiskyMac`.

```swift
Image("WhiskyMac")
    .renderingMode(.template)
    .font(.system(size: 15, weight: .regular))
    .imageScale(.medium)
```

For an AppKit status item, load the compiled catalog from its owning bundle:

```swift
let image = NSImage(symbolName: "WhiskyMac", bundle: bundle, variableValue: 0)?
    .withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 15, weight: .regular, scale: .medium)
    )
image?.isTemplate = true
statusItem.button?.image = image
```

The app loads this symbol from its SwiftPM resource bundle for the panel,
settings header, and normal menu-bar state. The compiled catalog is checked in
at `Sources/Whisk/WhiskyMacSymbols.bundle/Contents/Resources/Assets.car` because
SwiftPM's CLI does not compile asset catalogs. The separate bundle provides the
identifier required by CoreUI to load custom symbols. After editing the source
artwork, regenerate it with:

```sh
bash scripts/build-symbols.sh
```

This compiles both the WhiskyMac and LemonSlice catalogs. Appearance settings
provide independent normal/Privacy Mode icon choices, initially WhiskyMac and
LemonSlice. The searchable system-symbol index contains names only; images come
from `NSImage(systemSymbolName:)`, and unavailable symbols are filtered on the
user's macOS version. Refresh the index from an installed SF Symbols app with
`python3 scripts/update-symbol-names.py`. An exact system-symbol name can also be
entered in search even when it is newer than the bundled index.

## Validation

Compiled with Xcode actool 26.3 for macOS, deployment target 15.0. The resulting
asset catalog was loaded with AppKit and all 27 weight/scale combinations were
rendered successfully. Regular/Medium at 15 pt produces a 17 x 17 pt image.
All symbol contours are closed filled paths without SVG strokes or raster data.
After adding animation annotations, all 27 configurations were rendered again.
Native palette rendering confirmed three independently colored layers, and
AppKit accepted Bounce.byLayer and Pulse.byLayer with the compiled symbol.

Reference: [Apple - Creating custom symbols](https://developer.apple.com/documentation/technologyoverviews/custom-sf-symbols).
Animation annotations: [Apple - Annotating custom symbols](https://developer.apple.com/documentation/technologyoverviews/annotating-sf-symbols).
