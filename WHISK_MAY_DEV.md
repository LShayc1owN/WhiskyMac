# WhiskyMac

This development version is based on Whisk v1.0.3, commit
`1ebcee1e0735e957777c599017ee411d8046c7e7`, by Nathan Poncet and
contributors. The upstream Git history and license files are retained. May
changes in this checkout add a separate application identity, storage and
preferences isolation, opt-in global shortcuts, and development packaging.
The upstream `Whisk` Swift target name is intentionally retained.

## Local development identity

| Setting | Value |
| --- | --- |
| Bundle identifier and preferences suite | `dev.whisky.maclx` |
| App name | `WhiskyMac` |
| History directory | `~/Library/Application Support/WhiskMay-Dev` |
| Test-only directory override | `WHISK_MAY_DATA_DIR` |
| Minimum macOS version | 15.0 |

The original `WHISK_DATA_DIR` override is ignored. May does not import data
from the original Whisk directory. Its own directory still supports the
upstream JSON-to-SQLite import for May-owned historical files. Paths for
future imported icons and preview caches are defined under the May directory,
but those features do not write files yet.

Both global shortcuts start off. Each can be enabled in Settings or enabled
by recording its binding. Link previews start off. The upstream update check
is disabled for this development distribution, including if an old preference
claims it was enabled. Login items are registered only when chosen in Settings.

Build locally with `scripts/build-app.sh 0.0.5 native`. It produces
`dist/WhiskyMac.zip` containing an ad-hoc signed app. Extract the ZIP
before launching. The development package uses the WhiskyMac icon from
Assets/icon.icns and the custom symbol resources in Assets/Symbols.

Run `bash scripts/smoke-may-dev.sh` to verify the ZIP's signature and launch
the app with a temporary history directory. Smoke mode does not start
clipboard polling.

## History behavior in 0.0.2

Copies with the same payload and identical RTF bytes reuse the existing
entry. Different RTF bytes and a plain-text copy remain separate entries;
each follows the normal retention and pin rules. SQLite now persists edits
to existing IDs, including removal of stale formatting and undo restoration,
without updating unchanged content rows on reorder or pin changes. The
database schema is unchanged. Version 0.0.3 groups rich-text formats with identical plain text into one
module; plain copies stay independent.

The macOS 15 singular/plural labels and two layout regressions are fixed.
See `docs/research/step-2-implementation.md` for verification and
`docs/research/development-plan.md` for the remaining development order.

## License and scope

Whisk's GPL-3.0-or-later license and upstream copyright attribution remain
in place. The added files and modifications are part of this derivative work
under the same terms. This is a local development package, not a release or
an App Store submission. Third-party code and asset licenses should be
rechecked before public distribution; see `docs/LICENSING.md`. LinShay's
authorized App Store/TestFlight grant is in LICENSE-EXCEPTION-WHISKYMAC.md.

## Preview, interactions, and manual privacy in 0.0.3

Open a rich-text module to compare its two newest formats. The +x button
expands other formats. RTF is decoded only for mounted detail panes; the
native text view preserves fonts, colors, links and paragraph formatting.
Editing saves plain text and RTF together. Invalid RTF or RTF over 8 MiB
falls back to plain text. Pin, delete, stack and keyboard actions target the
newest version; copy, paste and edit gestures ask for a version when needed.
Grouped modules do not export a drag until a concrete format is chosen.

Settings offers separate single-click, double-click, right-click and hover
mappings. Defaults are preview, paste, menu and no action. Hover waits 700ms;
the ellipsis and VoiceOver Actions entry always provide the operation menu.
Paste restores the preceding app when possible and uses Accessibility access.
When permission is unavailable, copied content remains available for manual
Command-V. A failed global shortcut registration is reported in Settings.

Privacy Mode is available in the menu bar and Settings. Its optional global
shortcut starts disabled (Control-Option-Command-P is the suggested binding).
Manual protection persists across launches. Protected views receive empty
content DTOs, discard drafts and detail views, suppress accessibility children
and block content actions. Link and file preview requests are cancelled and
old results rejected. History itself is retained. Version 0.0.3 provided manual protection only; 0.0.5 adds the limited, opt-in
detector described below. Enable protection before displaying sensitive
content; content already exported to another app cannot be recalled.

The native surface implementation uses public system materials and
NSVisualEffectView, with no private backdrop filters or layer-tree inspection.

## Packaged startup fix in 0.0.4

Localization now resolves the shipped Contents/Resources/Whisk_Whisk.bundle
before any development layout. It does not call the generated Bundle.module
accessor or depend on a build-machine absolute path. Missing resources stop
packaging. Smoke tests verify the identity of the runtime resource directory;
WHISK_SMOKE_FINDER=1 also verifies a LaunchServices startup with temporary data.

## Sensitive sessions and limited automatic protection in 0.0.5

Settings offers sensitive source apps, ignored by default. A separate opt-in
retains their unmarked copies for 2 minutes in a bounded memory session, outside
normal history, undo, search and preview caches. Right-click or the ellipsis
reveals an entry for 10 seconds; closing the panel or enabling global protection
revokes that reveal. Rich text displays as plain text; images are copy-only.
Explicit concealed/transient/auto-generated markers remain unconditionally
excluded. Existing history is not reclassified. Source attribution is best effort.

Automatic protection starts off. The public Accessibility implementation checks
only specific Zoom/Teams sharing toolbar titles, with client-version and language
limitations. No system sharing, remote desktop, recorder or browser-tab coverage
is claimed. Real clients still require validation. Unknown results conservatively
hide content; scoped clear must be observed twice and remain stable for 5 seconds.
Automatic changes cannot clear manual protection. No private detector is included.

Build to a separate version directory without replacing the previous bundle:
`WHISK_PACKAGE_SUBDIR=0.0.5 scripts/build-app.sh 0.0.5 native`.
See `docs/research/stages-6-7-implementation.md` for boundaries and validation.

## Settings and Handoff hints in 0.0.6

Settings now has native top/sidebar navigation, runtime language selection
(system, English, French, German, Simplified Chinese), system/custom accent colors,
menu-bar click preferences, and three Dock icon policies. Defaults are top
tabs, system language/accent, click to show history, and Dock follows Settings
or welcome windows. Selection borders use the chosen accent.

New captures with the undocumented `com.apple.is-remote-clipboard` marker
show a Handoff hint rather than the current Mac app. Device/app identity is
unknown; missing markers do not establish local origin. Existing history is
not reclassified. An additive nullable SQLite column preserves the hint.

Build with `WHISK_PACKAGE_SUBDIR=0.0.6 scripts/build-app.sh 0.0.6 native`.
The archive is `dist/0.0.6/WhiskyMac 0.0.6.zip`. Smoke preferences are isolated
from the running app and cleaned at exit. Details and evidence are in
`docs/research/settings-enhancement-implementation.md`.

## Hover and manual spotlight in 0.0.7

Hover actions are now None or Preview, with a configurable 0.1–5 second dwell
(default 0.7). Old export/edit/menu hover actions migrate to None. Normal mode
opens the usual preview; manual privacy uses a small soft-edged spotlight
around the pointer and never opens a large preview. Automatic protection,
including uncertain detection, blocks the spotlight. Leaving a card or closing
the panel revokes it. Sensitive memory sessions remain separate.

The small revealed region is visible to screen recordings too. Rich text uses
a plain excerpt here; image thumbnails are temporary in-memory values.
See `docs/research/hover-privacy-implementation.md` for tests and limitations.
Build: `WHISK_PACKAGE_SUBDIR=0.0.7 scripts/build-app.sh 0.0.7 native`.

## Packaging hold (2026-11-02)

The user requested no new application packages, ZIPs or installers until they
explicitly request a new package. Source changes, builds and tests may continue.
The spotlight aspect-ratio/layout fix and wider feathered reveal are implemented
and tested but are not included in the existing archives. See
`docs/research/spotlight-layout-fix.md` for evidence.

## Protected search and source labels (source only)

Privacy settings now independently opt into search and source-app labels while
protection is active. Both start off and apply to manual and automatic modes.
Search filters masked normal-history cards; it does not publish content snippets
or include sensitive memory sessions. The query and explicitly enabled app names
are visible and accessible. Automatic protection still blocks hover reveals.
Pending queries are cancelled and cleared when search permission is revoked, the
panel closes, or protection changes. No package was generated for this change.
See `docs/research/privacy-display-options.md` for validation.

## Preview dismissal (source only)

Hover-opened large previews close 0.4 seconds after leaving the source card;
reentry cancels the close. Explicit preview actions remain open until triggered
again or until history closes. An explicit action can promote a hover preview,
invalidating its old close callback. Hover previews stay bound to their source
card until the next dwell completes. Privacy spotlight dismissal is unchanged.
See `docs/research/preview-dismissal.md`; no package was generated.

## Copy sounds (source only)

General settings offer separate, initially disabled sounds for successful ordinary
capture and explicit history copy. Every paste route stays silent. Three CC0
Kenney clicks (default Click 4) are bundled; licensing/source notices are in
docs/licenses. Pop/Tink/Glass remain runtime macOS choices with volume/audition. Automatic feedback is muted
while protected; sensitive captures and exports stay silent. Playback is limited
to once per 120ms and stops before another sound starts. No Apple audio assets are
copied, no code dependencies added, and no package generated. See
`docs/research/copy-sound.md` for policy, licensing candidates and test evidence.

## Application filters (source only, 2026-11-03)

Interactions settings select Click (default) or Hover. Hover waits 250ms and
switches to one app; click and keyboard still toggle selections. All leads the
filter row, clears app/type/pinned filters and keeps the query. Cancelled, hidden
or privacy-blocked hover work cannot change filters. See
docs/research/app-filter-interaction.md for validation; no package generated.
