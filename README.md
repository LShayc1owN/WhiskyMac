# WhiskyMac

[English](README.md) | [简体中文](README.zh-CN.md)

Repository: [lshayc1own/WhiskyMac](https://github.com/lshayc1own/WhiskyMac).
This checkout is being prepared for a private development repository; public
binary distribution has not been configured.

WhiskyMac is a clipboard manager for macOS, developed from
[Whisk v1.0.3](https://github.com/nathan-poncet/whisk/tree/1ebcee1e0735e957777c599017ee411d8046c7e7)
by Nathan Poncet and contributors. Upstream base:
`1ebcee1e0735e957777c599017ee411d8046c7e7`.

This is an independent modified version maintained by **LinShay (琳曦)**.
It is not an official Whisk release and does not imply upstream endorsement.
Modifications are documented as of **2026-11-03**.

## Features

- Local clipboard history for text, rich text, links, images, files and colors.
- Search, application/category filters, pins, retention rules and a paste stack.
- Rich-text version grouping, configurable card interactions and previews.
- Manual privacy protection, optional sharing detection and temporary sensitive sessions.
- Configurable appearance, keyboard shortcuts and optional copy sounds.
- English, French, German and Simplified Chinese interface.

See [development notes](WHISK_MAY_DEV.md) for implementation details and
limitations. The software is currently a development build.

## Build and verify

Requires macOS 15 or later and the macOS 26 SDK. Tests and resource generation
require a full Xcode installation.

Run from this checkout:

```sh
swift run Whisk
swift test
./scripts/localizations.sh check
./scripts/build-app.sh 0.0.0 native
```

The packaging script creates `dist/WhiskyMac.app` and `dist/WhiskyMac.zip`.
The internal Swift target and executable remain `Whisk`; this preserves the
existing module and resource layout. Without a signing identity the app is
signed ad hoc; this does not establish notarization or App Store eligibility.

## Data and privacy

The bundle identifier is `dev.whisky.maclx`. Existing development history stays
in `~/Library/Application Support/WhiskMay-Dev`; renaming the app does not migrate
or delete history. `WHISK_MAY_DATA_DIR` overrides this location for isolated tests.
WhiskyMac does not import the upstream Whisk history automatically.

Global shortcuts and link previews start disabled. Link previews, when enabled,
request metadata from the copied website. Update checks are disabled for this
development distribution. Direct paste and optional sharing detection can require
macOS permissions. Privacy protection does not recall content already exported
to another application.

## License and attribution

The software is licensed under **GPL-3.0-or-later**, except separately licensed
third-party material. Preserve [LICENSE](LICENSE), [NOTICE](NOTICE) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

- Original Whisk: copyright 2026 Nathan Poncet and contributors.
- WhiskyMac modifications: copyright 2026 LinShay (琳曦), to the extent of rights held.
- Upstream App Store/TestFlight permission:
  [original grant](LICENSE-EXCEPTION-APP-STORE.md), retained verbatim.
- LinShay's permission for authorized WhiskyMac additions:
  [separate grant](LICENSE-EXCEPTION-WHISKYMAC.md).

The upstream exception expressly includes works based on Whisk. These grants
address copyright permission for that distribution channel; Apple review,
signing and rights in third-party material remain separate requirements.
The Neovim mark is by Jason Long under CC BY 3.0; the bundled Kenney UI Audio
sounds are by Kenney Vleugels under CC0. See the third-party notices for details.

When distributing binaries, supply the complete source corresponding to that
version, including modifications, assets in their preferred editable form and
necessary build scripts, under the applicable terms. Linking only to the
unmodified upstream source is insufficient. App Store/TestFlight distribution
under the exceptions requires that source to remain publicly available.
No copyright assignment, paid license or “GPL certificate” is needed merely to
maintain this fork.

## Release configuration

The development repository is intended to be private. Public source access,
support and privacy policy URLs are not yet configured. Set the public
addresses in [release-config.json](release-config.json)
before external binary distribution. Blank fields intentionally fail the
release validation. No upstream account or website is used as this project's
distribution destination.

Legal files are copied into packaged apps under `Contents/Resources/Legal`
and are accessible from the menu bar's **Licenses and notices…** item.
See [licensing review](docs/LICENSING.md) for verified sources and remaining
publication details. Existing compiled archives in `disc/` are old local
artifacts; rebuild from source to obtain the renamed app with these notices.

Contributions follow [CONTRIBUTING.md](CONTRIBUTING.md). Architecture:
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
