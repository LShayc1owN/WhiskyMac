# Third-party notices

This file records the third-party materials distributed in the source tree and
the notices needed when distributing WhiskyMac. It supplements, and does not
replace, [LICENSE](LICENSE) or the original license files kept with the assets.

## Whisk

WhiskyMac is derived from Whisk v1.0.3 at commit
`1ebcee1e0735e957777c599017ee411d8046c7e7`.

- Copyright: Nathan Poncet and contributors.
- Source: <https://github.com/nathan-poncet/whisk>
- License: GNU General Public License, version 3 or later (GPL-3.0-or-later).
- App Store additional permission: retained in
  [LICENSE-EXCEPTION-APP-STORE.md](LICENSE-EXCEPTION-APP-STORE.md).

## Neovim mark

`Sources/Whisk/Resources/nvim.png` and `docs/media/nvim.png` contain the
Neovim mark used for the code-category icon.

- Author: Jason Long.
- License: [Creative Commons Attribution 3.0 Unported (CC BY 3.0)](https://creativecommons.org/licenses/by/3.0/).
- Attribution source: <https://store.neovim.io/products/neovim-sticker-logo-only>.
- These PNG files are retained from Whisk v1.0.3 without further modification
  in WhiskyMac. The upstream conversion history has not been independently
  established. Their use here is as a code-category icon.

This attribution does not imply endorsement by Neovim or its contributors.

## Kenney UI Audio

`Sources/Whisk/Resources/Sounds/kenney-*.wav` are nine UI sounds from
Kenney UI Audio by Kenney Vleugels (Kenney.nl): click1–5, mouseclick1,
mouserelease1, rollover2 and switch14.

- License: [Creative Commons Zero 1.0 Universal (CC0-1.0)](https://creativecommons.org/publicdomain/zero/1.0/).
- Source: <https://kenney.nl/assets/ui-audio>.
- Changes: converted from the source OGG files to WAV and renamed with the
  `kenney-` prefix; no other modifications.
- Preserved source license and provenance: [docs/licenses/Kenney-UI-Audio.txt](docs/licenses/Kenney-UI-Audio.txt) and [docs/licenses/Kenney-UI-Audio-source.md](docs/licenses/Kenney-UI-Audio-source.md).

CC0 does not require attribution; this notice is retained for provenance.

## SFX Kit

Four `Sources/Whisk/Resources/Sounds/sfx-*.wav` sounds from SFX Kit by Wyzowl:
soft button, soft tap, soft snap and small bubble.

- License: Creative Commons Zero 1.0 Universal (CC0-1.0).
- Source: <https://github.com/wyzowl/sfx-kit> at
  `92780e7ab0cdfb557497a988089c47f46e8c7412`.
- Files are renamed only; audio bytes are unchanged. No upstream code is bundled.
- License: [docs/licenses/SFX-Kit-CC0.txt](docs/licenses/SFX-Kit-CC0.txt).
- Provenance: [docs/licenses/SFX-Kit-source.md](docs/licenses/SFX-Kit-source.md).
- Import hashes: [docs/licenses/copy-sound-assets.json](docs/licenses/copy-sound-assets.json).

CC0 does not require attribution; this notice is retained for provenance.

## WhiskyMac artwork and generated resources

The app icon in `Assets/icon.png` / `Assets/icon.icns` and custom artwork in
`Assets/Symbols/` are WhiskyMac additions. Source SVGs are kept alongside the
compiled `Sources/Whisk/WhiskyMacSymbols.bundle` resource. LinShay's license
grant covers only rights LinShay holds or is authorized to grant; it does not
grant rights in Apple symbols, trademarks, or other third-party material.

## System-provided material

Apple frameworks are used through the macOS SDK and are not redistributed as
part of this repository. Application icons shown in clipboard history are
obtained at runtime from the user's installed applications. Those icons and
their associated marks belong to their respective owners and are not licensed
by this project.
