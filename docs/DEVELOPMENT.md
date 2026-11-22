# WhiskyMac development

WhiskyMac is based on Whisk v1.0.3, commit
`1ebcee1e0735e957777c599017ee411d8046c7e7`. The Swift target and executable
remain `Whisk`. See ../NOTICE and ../LICENSE for attribution and licensing.
Current scope and maintenance priorities are in [PROJECT.md](PROJECT.md);
dependency boundaries are in [ARCHITECTURE.md](ARCHITECTURE.md).

## Build and verification

Use macOS 15 or later and the macOS 26 SDK. Resource generation and tests
require full Xcode.

```sh
./scripts/localizations.sh check
./scripts/check-dependency-rule.sh
swift format lint --strict --recursive Sources Tests Package.swift
swift build
swift test
```

Edit `Sources/Whisk/Resources/Localizable.xcstrings` for translations, then run
`./scripts/localizations.sh generate`. Commit the catalog and generated language
resources together. The interface supports English, French, German, Italian and
Simplified Chinese. Custom symbol sources are in `Assets/Symbols`; compile them
with `bash scripts/build-symbols.sh` when changing the artwork.

When a package is needed, run `./scripts/build-app.sh <version> native` (or
`universal`). Set `WHISK_PACKAGE_SUBDIR` to an explicit child name to avoid
replacing other outputs. The default build writes to `dist/`, replacing that
output directory. A build without a signing identity is signed ad hoc.

`bash scripts/smoke-may-dev.sh <archive.zip>` verifies an extracted archive and
runs isolated startup checks without clipboard polling. It uses temporary
history and preferences. It does not read or migrate the user's history.

## Identity and storage

- Display name: WhiskyMac.
- Bundle identifier and preferences: `dev.whisky.maclx`.
- Development history: `~/Library/Application Support/WhiskMay-Dev`.
- Isolated test override: `WHISK_MAY_DATA_DIR`; upstream `WHISK_DATA_DIR` is ignored.

The renamed app retains the development data location. It does not import the
upstream Whisk data automatically. The packaged resource bundle remains
`Contents/Resources/Whisk_Whisk.bundle` and must ship inside the app.

## Behavior and limitations

- Settings → Debug → Show first-launch guide replays onboarding from the welcome
  page and clears its simulated practice session. It preserves the completion
  flag, reuses an open guide window and does not request permissions until the
  corresponding action is chosen. The entry is also available in Settings search
  and in both top-tab and sidebar navigation.

- Global shortcuts, link previews and sharing detection start disabled.
  Update checks at launch start disabled; manual checks and opt-in launch checks
  use the WhiskyMac stable-release feed. Automatic attempts are limited to once
  per 24 hours. App Store builds omit external updates. Login items register
  only when chosen in Settings.
- Rich-text versions with identical plain text group together; plain-text
  copies stay independent. Copying or editing a particular version requires
  selecting it. Invalid or oversized RTF falls back to plain text.
- Privacy protection masks raw content and blocks full preview, editing and
  splitting. Explicit copy/paste follows the separate privacy interaction
  profile. Search and card source labels while protected are independent
  opt-ins and can themselves reveal the query and application names. App
  filters default on independently; other filters start off. Protection cannot
  recall exports.
- Optional sharing detection uses public Accessibility information from
  selected Zoom/Teams sharing-toolbar titles. Client-version and language
  limitations apply. It does not establish system-wide screen-sharing,
  recording, remote-desktop or browser-tab detection. The application starts in
  normal mode. After sharing is observed, unknown detector results keep content
  hidden; automatic state cannot clear manual protection.
- Sensitive source applications use a bounded in-memory session immediately,
  separate from normal history, search, undo and preview caches. Retention is
  configurable from 1 to 1440 minutes, default 2; an explicit reveal lasts ten
  seconds and is revoked when the panel closes or global protection activates.
  Excluded applications and concealed, transient or generated clipboard markers
  are never recorded. Existing history is not reclassified.
- Manual privacy spotlight reveals a small region near the pointer. That
  region is also visible to screen recordings. Automatic protection blocks
  spotlight reveals. Hover previews close after leaving the card, whereas
  explicit previews remain open until dismissed.
- Handoff attribution is a best-effort hint from a clipboard marker. It
  cannot identify the remote device/application, and an absent marker does
  not establish local origin.
  The Handoff chip occupies a separate origin group before app chips and is not
  collapsed with More apps. Selecting Handoff clears app filters and selecting
  an app clears Handoff; type, pin and tag constraints can still be combined.
  Hide by type or source can hide Handoff entries before a chosen cutoff without
  deleting or saving them. Its independent Privacy Mode permission initially
  follows the saved app-filter permission, then persists separately.
- Capture/copy sounds are opt-in. Paste operations, sensitive exports and
  protected activity remain silent. Bundled sounds and their source notices
  are listed in ../THIRD_PARTY_NOTICES.md.
- Startup hands a validated lightweight snapshot to the controller. Image and
  RTF originals remain in immutable SQLite revisions and are read on demand.
  Panel close and protection changes release content/preview caches; memory
  pressure also clears reusable app-icon resources. Cache budgets are not a
  fixed limit on the application's total memory.

## Repository contents

Track source, tests, editable assets, build scripts and licensing documents.
Keep local agent notes, acceptance reports, screenshots and video editing
workspaces outside version control. `.gitignore` lists their local locations.
Publish installable packages through GitHub Releases together with the
corresponding source; do not commit installers or signing credentials.
See LICENSING.md and ../release-config.json before configuring publication.
