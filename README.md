<p align="center"><img src="Assets/icon.png" width="112" alt="WhiskyMac app icon"></p>
<h1 align="center">WhiskyMac</h1>
<p align="center">Keep what you copy close at hand.<br>Clipboard history for macOS 15 and later.</p>
<p align="center"><a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.zh-TW.md">繁體中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.fr.md">Français</a> · <a href="README.de.md">Deutsch</a> · <a href="README.it.md">Italiano</a></p>

> [!NOTE]
> WhiskyMac is under active development as an independent project based on [Whisk](https://github.com/nathan-poncet/whisk). The features below describe the current source tree. Check the release notes for the features and signing status of each download.

## Download and get started

**[Latest GitHub release](https://github.com/LShayc1owN/WhiskyMac/releases/latest)**

1. Under **Assets**, download the `WhiskyMac-v*.zip` app package. Unzip it and move `WhiskyMac.app` to Applications.
2. Open WhiskyMac and follow the Welcome Guide. If clipboard access is required, right-click the WhiskyMac icon in the menu bar and choose **Allow Clipboard Access…**.
3. Copy something in another app, then click the WhiskyMac menu bar icon or choose **Show History** to find it. You can enable a global shortcut in Settings.

## Highlights

- **Find your clips.** Text, rich text, code, links, images, files and colors are kept locally. Search by content or source app with fuzzy, contains, whole-word, starts-with or ends-with matching. Filter by app, type, pins, color tags or Handoff. Use `type:path` to find file paths copied as text.
- **Reuse clips.** Preview, edit, drag, copy, paste directly or as plain text, and queue clips for pasting. Choose among grouped rich-text versions and navigate with the keyboard or optional Vim bindings.
- **Split and organize.** Split text by lines, paragraphs or separators, or extract HTTP(S) links. Review the parts, then add cards, replace the original or save a group. When copying or pasting a group, choose the original or selected parts.
- **Keep history organized.** Pin clips with searchable notes, seven color tags and an option to always hide their contents. Open pins in the history panel or in a separate window. Temporarily hide older clips by time, content type or Handoff source. Set the retention and capacity for unpinned history, or clear it with an Undo option.
- **Control what’s visible.** Manual Privacy Mode masks cards and lets you configure search, filters and pointer-area reveal. You can also reveal a single card in place from its menu. Optional Zoom/Teams screen-sharing detection covers supported sharing toolbars. Copies from sensitive apps expire in memory, and excluded apps are skipped.
- **Mask likely secrets.** Local recognition looks for common API keys, tokens, cookies and hashes. Card masking and categorization under **Secret** are separately configurable. Masking controls what the card displays.
- **Match your Mac.** macOS 26 and later use native Liquid Glass for controls in history and Settings. macOS 15 uses a frosted interface. Choose light, dark or system appearance independently for the history panel and Settings.
- **Make it yours.** Adjust card size, the menu bar icon, card interactions, keyboard shortcuts and optional copy sounds. Search Settings or reset shortcuts by category with Undo. The interface supports English, French, German, Italian, Simplified Chinese, Traditional Chinese and Japanese.

For detailed behavior and limits, see the [project scope](docs/PROJECT.md) and [changelog](CHANGELOG.md).

## Privacy and data

- WhiskyMac stores history in `~/Library/Application Support/WhiskyMac` under bundle ID `dev.whisky.maclx`. Upstream Whisk history is not imported automatically. Use `WHISKYMAC_DATA_DIR` for isolated tests.
- Global shortcuts, link previews, sharing detection and launch-time update checks start off. Enabled link previews request metadata from the copied website. Manual and opt-in automatic update checks use WhiskyMac's stable GitHub releases; App Store builds omit external update checks.
- Direct paste and optional sharing detection can need macOS permissions. Handoff attribution is a best-effort hint, not a verified device or app identity. Privacy Mode cannot recall content already exported to another app.

More detail: [development notes](docs/DEVELOPMENT.md).

## Origin and license

WhiskyMac is an independent modification of [Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7) (base commit `1ebcee1e0735e957777c599017ee411d8046c7e7`). The [original project](https://github.com/nathan-poncet/whisk) is by Nathan Poncet and contributors. WhiskyMac is maintained by **LinShay (琳曦)**; it is not an official Whisk release or an upstream endorsement.

The software is **GPL-3.0-or-later**, except for separately licensed third-party material. Keep the [license](LICENSE), [project notice](NOTICE) and [third-party notices](THIRD_PARTY_NOTICES.md). Original Whisk portions are © 2026 Nathan Poncet and contributors; WhiskyMac additions are © 2026 LinShay (琳曦) to the extent of rights held.

The [upstream App Store/TestFlight exception](LICENSE-EXCEPTION-APP-STORE.md) is retained verbatim. LinShay's [separate exception](LICENSE-EXCEPTION-WHISKYMAC.md) covers additions LinShay can license. Binary distribution requires the complete corresponding source for that version; distribution under these exceptions requires it to remain publicly available. Apple review, signing and third-party rights have separate requirements. The Neovim mark is CC BY 3.0; bundled Kenney UI Audio and Wyzowl SFX Kit sounds are CC0. See the [licensing review](docs/LICENSING.md) for details.

## Releases and support

Read the notes and find downloads for earlier versions on [GitHub Releases](https://github.com/LShayc1owN/WhiskyMac/releases). In the app, open the bundled legal notices from **Licenses and Notices…** in the WhiskyMac menu.

If WhiskyMac helps you, you can support its independent development with a voluntary donation:

<a href="https://www.buymeacoffee.com/funclinkrev"><img src="https://img.buymeacoffee.com/button-api/?text=Buy me a coffee&amp;emoji=&amp;slug=funclinkrev&amp;button_colour=FFDD00&amp;font_colour=000000&amp;font_family=Cookie&amp;outline_colour=000000&amp;coffee_colour=ffffff" alt="Buy me a coffee"></a>

[WhiskyMac supporters](https://github.com/LShayc1owN/WhiskyMac-supporters)

## More information

[Project scope](docs/PROJECT.md) · [Development guide](docs/DEVELOPMENT.md) · [Architecture](docs/ARCHITECTURE.md) · [Changelog](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)
