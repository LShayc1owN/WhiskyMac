# LemonFruit custom SF Symbol

An original whole lemon with softly pointed ends, a curved rind highlight in
negative space, and paired leaves matching the other WhiskyMac citrus symbols.

- `LemonFruit.svg`: standalone 24-unit Regular vector artwork.
- `LemonFruit.xcassets/LemonFruit.symbolset/LemonFruit.svg`: annotated SF Symbols
  template with nine weights and three scales (27 explicit variants).
- `LemonFruit-preview.png`: light/dark previews, small sizes, and weight comparison.

The template uses format 7.0 and requires Xcode 26 or later. All contours are
closed filled paths. Fruit, large leaf, and small leaf have three distinct
rendering layers and motion groups, so each can move independently. Transparent
erase layers travel with their respective leaves to maintain overlap gaps.
The fruit highlight and leaf veins are negative space within their owning shape.
The plain SVG also names the `fruit`, `large-leaf`, and `small-leaf` groups.
Bounce, Wiggle, and Pulse can use `byLayer`.
Draw On/Off guide points are not supplied.

The symbol is compiled by `bash scripts/build-symbols.sh` and is available in the
menu-bar icon picker. The asset name is `LemonFruit`; existing preferences and
defaults are preserved.

```swift
Image("LemonFruit", bundle: AppSymbol.bundle)
    .symbolRenderingMode(.monochrome)
    .font(.system(size: 17, weight: .regular))
    .symbolEffect(.bounce.byLayer, value: trigger)
```
