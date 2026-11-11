# Components

Small, reusable implementations used by WhiskyMac live here. Keep only the
behavior the app calls, and keep the private PetaToolKit and PetaKitUIX packages
out of this repository's dependencies.

When reviewing new app code, move repeated view behavior here when it makes
call sites clearer. Keep clipboard and presentation decisions in their existing
architecture layers.

Use `beButton` for custom view labels, including labels that need a button
role. Keep the native titled `Button` initializer where it is shorter.

`IndexedForEach` accepts identifiable elements directly or an explicit `id`
key path for other collections. `SettingsRowLabel` gives settings controls a
consistent icon and title layout.
