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

The symbol template uses format 7.0 from the installed Apple SF Symbols tool.
Use Xcode 26 or later to compile the asset catalog. The symbol is monochrome;
color comes from the containing UI. All 27 variants are explicit static designs,
so vector interpolation and animation annotations are not required.

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

## Validation

Compiled with Xcode actool 26.3 for macOS, deployment target 15.0. The resulting
asset catalog was loaded with AppKit and all 27 weight/scale combinations were
rendered successfully. Regular/Medium at 15 pt produces a 17 x 17 pt image.
All symbol contours are closed filled paths without SVG strokes or raster data.

Reference: [Apple - Creating custom symbols](https://developer.apple.com/documentation/technologyoverviews/custom-sf-symbols).
