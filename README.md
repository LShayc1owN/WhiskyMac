<p align="center"><img src="Assets/icon.png" width="112" alt="WhiskyMac app icon"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">Keep what you copy close at hand.<br>Clipboard history for macOS 15 and later.</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac is an independent modification of [Whisk](https://github.com/nathan-poncet/whisk). It is in development: this repository is private, and public app downloads are not configured yet. The instructions below are for building from this checkout.

## Highlights

- **Find your clips.** Keep text, rich text, links, images, files and colors locally. Search content or source apps; filter by app, type, pins, color tags and Handoff attribution. Text containing file paths has its own filter and supports `type:path`.
- **Reuse content your way.** Copy, paste directly or as plain text, drag into another app, preview, edit and queue clips in the paste stack. Matching rich-text versions stay grouped; keyboard and optional Vim navigation are available.
- **Split and organize.** Split text by lines, paragraphs or separators, or extract HTTP(S) links. Review the parts, then add cards, replace the original or save a group. Choose the original or individual group parts when copying or pasting.
- **Keep important items.** Pins can have searchable notes, seven color tags and permanently masked content. View pins in history or a separate window. Set retention and capacity for unpinned history; clearing it supports Undo.
- **Control what appears.** Manual Privacy Mode masks the panel. Optional Zoom/Teams sharing-toolbar detection has limited coverage. Search, filters and a pointer-area reveal can be enabled separately while content stays masked. Sensitive apps use an expiring memory-only session; excluded apps are not captured.
- **Make it yours.** Customize card size, frosted appearance, status icon, interactions, shortcuts and optional copy sounds. Settings search and shortcut-reset Undo simplify changes. A first-run practice space leaves your real clipboard and history untouched. The interface supports English, French, German, Italian, Simplified Chinese, Traditional Chinese and Japanese.

For detailed behavior and limits, see the [project scope](docs/PROJECT.md) and [changelog](CHANGELOG.md).

## Build from source

You need macOS 15 or later, the macOS 26 SDK and a full Xcode installation. From this checkout:

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

The packaging script creates `dist/WhiskyMac.app` and `dist/WhiskyMac.zip`. The internal Swift target and executable are still named `Whisk`. Without a signing identity, the package is signed ad hoc; it is not notarized or ready for App Store submission.

## Privacy and data

- History stays in `~/Library/Application Support/WhiskMay-Dev` under bundle ID `dev.whisky.maclx`. The rename does not move or delete existing development history, and upstream Whisk history is not imported automatically. Use `WHISK_MAY_DATA_DIR` for isolated tests.
- Global shortcuts, link previews, sharing detection and launch-time update checks start off. Enabled link previews request metadata from the copied website. Manual and opt-in automatic update checks use WhiskyMac's stable GitHub releases; App Store builds omit external update checks.
- Direct paste and optional sharing detection can need macOS permissions. Handoff attribution is a best-effort hint, not a verified device or app identity. Privacy Mode cannot recall content already exported to another app.

More detail: [development notes](docs/DEVELOPMENT.md).

## Origin and license

WhiskyMac is an independent modification of [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7) (base commit `1ebcee1e0735e957777c599017ee411d8046c7e7`). The [original project](https://github.com/nathan-poncet/whisk) is by Nathan Poncet and contributors. WhiskyMac is maintained by **LinShay (琳曦)**; it is not an official Whisk release or an upstream endorsement.

The software is **GPL-3.0-or-later**, except for separately licensed third-party material. Keep the [license](LICENSE), [project notice](NOTICE) and [third-party notices](THIRD_PARTY_NOTICES.md). Original Whisk portions are © 2026 Nathan Poncet and contributors; WhiskyMac additions are © 2026 LinShay (琳曦) to the extent of rights held.

The [upstream App Store/TestFlight exception](LICENSE-EXCEPTION-APP-STORE.md) is retained verbatim. LinShay's [separate exception](LICENSE-EXCEPTION-WHISKYMAC.md) covers additions LinShay can license. Binary distribution requires the complete corresponding source for that version; distribution under these exceptions requires it to remain publicly available. Apple review, signing and third-party rights have separate requirements. The Neovim mark is CC BY 3.0; bundled Kenney UI Audio and Wyzowl SFX Kit sounds are CC0. See the [licensing review](docs/LICENSING.md) for details.

## Releases and support

Public source, support and privacy-policy URLs are still blank in [release-config.json](release-config.json); release validation rejects them until configured. Installable builds should be published through GitHub Releases with corresponding source, not committed as packages. Packaged apps include legal files in `Contents/Resources/Legal`, accessible through **Licenses and notices…** in the menu bar.

If WhiskyMac helps you, you can support its independent development with a voluntary donation:

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="Buy me a coffee"></a>

[WhiskyMac supporters](https://github.com/LShayc1owN/WhiskyMac-supporters)

## More information

[Project scope](docs/PROJECT.md) · [Development](docs/DEVELOPMENT.md) · [Architecture](docs/ARCHITECTURE.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)
