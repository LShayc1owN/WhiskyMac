# WhiskyMac

This development version is based on Whisk v1.0.3, commit
`1ebcee1e0735e957777c599017ee411d8046c7e7`, by Nathan Poncet and
contributors. The upstream Git history and license files are retained. This
checkout adds a separate application identity, storage and
preferences isolation, opt-in global shortcuts, and development packaging.
The upstream `Whisk` Swift target name is intentionally retained.

## Local development identity

| Setting | Value |
| --- | --- |
| Bundle identifier and preferences suite | `dev.whisky.maclx` |
| App name | `WhiskyMac` |
| History directory | `~/Library/Application Support/WhiskyMac` |
| Test-only directory override | `WHISKYMAC_DATA_DIR` |
| Minimum macOS version | 15.0 |

WhiskyMac reads `WHISKYMAC_DATA_DIR` for isolated tests. It supports
JSON-to-SQLite import for historical files in the selected WhiskyMac directory.

Both global shortcuts start off. Each can be enabled in Settings or enabled
by recording its binding. Link previews and launch-time update checks start
off. Login items are registered only when chosen in Settings.

Build locally with `scripts/build-app.sh 0.0.5 native`. It produces
`dist/WhiskyMac.zip` containing an ad-hoc signed app. Extract the ZIP
before launching. The development package uses the WhiskyMac icon from
Assets/icon.icns and the custom symbol resources in Assets/Symbols.

Run `bash scripts/smoke-whiskymac-dev.sh` to verify the ZIP's signature and launch
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

## Sensitive access (source changes, not yet packaged)

Privacy → Sensitive access now contains both app lists. Sensitive apps always
retain unmarked copies temporarily; there is no second opt-in toggle. The shared
limit defaults to 2 minutes and accepts whole minutes from 1 to 1440 through a
keyboard field or stepper. Excluded apps are never recorded. Adding an app to one
list removes it from the other. No legacy-settings migration is included during
this single-developer phase.

Sensitive copies remain in a bounded memory-only store, outside normal history,
undo, search and preview caches. Expiry removes the entry with no undo or app
restart recovery. Lowering the limit applies from each existing copy's original
capture time; raising it only affects new copies. Reveal and copy never renew the
retention deadline. Entries can disappear earlier on quit/sleep, app-rule changes
or memory-cap eviction (10 entries / 16 MiB). Right-click or the ellipsis reveals
an entry for 10 seconds; closing the panel or enabling global protection revokes
that reveal. Rich text displays as plain text; images are copy-only.

Explicit concealed/transient/auto-generated markers remain unconditionally
excluded. Existing normal history is not reclassified. Source attribution is best
effort. Expiry does not clear the system clipboard or other apps' copies, and
releasing Swift values is not a guarantee of physical memory erasure or prevention
of OS swap. No new app package was generated.

## Limited automatic protection (introduced in 0.0.5)

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
capture and explicit history copy. Every paste route stays silent. Nine CC0
Kenney sounds (default Click 4) and four CC0 Wyzowl SFX Kit sounds are bundled;
licensing/source notices and pinned import hashes are in docs/licenses. The menu
groups Kenney, SFX Kit and runtime macOS Pop/Tink/Glass, for 16 choices total,
with volume/audition. The 10 new samples add only 106,270 bytes and all last under
0.15 seconds. Automatic feedback is muted
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

## Clear history and privacy shortcut (source only, 2026-11-03)

The history toolbar has a Clear button for all unpinned history, including hidden
results. Pins are preserved and Command-Z can undo. Empty, protected, hidden and
editing states cannot clear through a stale button; previews are dismissed first.
The default manual-privacy shortcut is Command-Option-P; custom bindings remain
untouched, and initial global registration is still off. 418 tests pass. See
docs/research/clear-history-shortcut.md. No package generated.

## Privacy hover reveal settings (source only, 2026-11-03)

Privacy settings expose reveal diameter (40-320 points, default 150) and soft
edge radius (0-80 points, default 50, capped at half the diameter). Values update
mounted cards live, persist independently and can reset to defaults. Zero blur
uses a hard circle; the soft edge uses the existing bounded radial mask. Only
manual hover preview may reveal; automatic protection stays fully masked.
See docs/research/privacy-hover-settings.md. No package generated.

## Rich text in history cards (source only, 2026-11-03)

Mounted history cards render RTF with native AppKit drawing, preserve formatting,
and keep card gestures. Decoding is reused per mounted surface; teardown clears
the data and attributed objects. Card parsing is capped at 256 KiB and excerpts
at 4000 UTF-16 units, with plain-text fallback. Full previews retain their separate
budget. No new global cache or package. See docs/research/rich-text-cards.md.

Privacy hover defaults now use 150/50 points. Both controls accept whole-point
keyboard input committed on Return or focus loss, with clamping and invalid-draft
reversion. Existing saved settings are preserved. 29 related tests pass; no package.

## Filters in Privacy Mode (source only, 2026-11-04)

Privacy settings independently control app filters (default on) and other filters
(default off). App names/icons appear in the filter bar when allowed; card source
labels remain a separate opt-in. All, pinned, type and tag filters work on masked
results according to the granted permissions. Revoked permissions and closed panels reject stale
actions, and automatic protection still blocks content reveal. No package
generated. See docs/research/privacy-filtering.md for scope and validation.

## AudioQueue copy effects (source only, 2026-11-04)

Copy feedback now uses AudioToolbox PCM output rather than NSSound. Existing
choices, volume and privacy/paste silence rules remain. Queues are disposed after
completion; only bounded decoded samples are cached. No MusicKit/Now Playing,
remote commands, recording, exclusive device or ducking setup. Tests use fake
output; actual music coexistence and OS activity indicators remain unverified.
464 tests pass. See docs/research/copy-sound-audioqueue.md. No package generated.

## Mode-specific card actions (source only, 2026-11-04)

Interaction settings now have normal and privacy groups with independent click
and hover bindings/timing. Existing normal settings stay; a one-time migration
copies only the old hover setting to the private profile. Privacy clicks start
as none/none/menu. Per the user's explicit choice, privacy clicks/menu may copy
or paste after a version choice for grouped records. Full preview/edit remain
blocked; reveal stays local/manual only. Generic keyboard/export guards remain.
No package. See docs/research/interaction-modes.md for scope and pending UI checks.


## Pinned items extension (source only, 2026-11-08)

Pinned item actions offer notes (up to 200 characters), an always-hide switch and
seven color tags. Notes remain visible aliases; explicit copy/paste still exports
the original. The hidden display DTO has no raw text/image/RTF/path/drag bytes,
and does not feed online link previews. Global privacy and no-record capture
policies still take priority. This is display masking, not encryption or expiry.

History settings select aggregated history or a separate window (default), with
pointer-positioned list (default) or bottom cards. A separate window stays pinned
through All/reset and deletion. The independent Control-Option-Command-V binding
starts disabled until enabled/recorded in Settings. A menu entry also opens pins.
Both windows share one data controller and close each other on switching. No app
package generated. See docs/research/pinned-items.md for contracts and validation.


## Content splitting (source only, 2026-11-10)

Settings → Interactions → Normal mode offers Split… as an action for single,
double and right clicks. Hover stays none/preview; privacy excludes splitting.
The card action menu retains the manual Split… entry. Both paths open the same
local rules, selectable previews and save modes.
Lines/paragraphs, literal punctuation/Tab/custom separators and visible/RTF HTTP(S)
link targets are supported. Preserve RTF by default or explicitly choose plain
text. Keep original/add, replace, and grouped results each save atomically with
one undo. Capacity is assessed and old-history eviction requires confirmation;
selected parts are never silently dropped. Original/part group selection happens
before every copy/paste route, with ordered multi-select and original exclusivity.

Groups count as one item and preserve parent pin/note/tag/hide policy. No nested
groups, group editing, child deletion, whole-group dragging/exporting or paste
stack in this version. Hidden/global privacy/sensitive sessions cannot split;
source changes, protection or close clear drafts. No online metadata is fetched
by analysis or its previews. Independent RTF parts keep split provenance so they
do not collapse into existing automatic format groups.

Limits: 1 million UTF-16 units, 8 MiB RTF parsing, 1000 candidates. Five languages
are maintained. See docs/research/content-splitting.md for UI interfaces and test
evidence. No app/ZIP generated, no commits or remote operations.


## Shortcut category reset (source only, 2026-11-11)

Settings → Shortcuts → Reset has independent checkboxes for global, inside-panel,
and Vim bindings. All are checked by default; any combination is supported, and
empty selection disables reset. Confirmation lists the selected scopes. Global reset
also turns those shortcuts off and clears their registration failures; panel/Vim
reset leaves global bindings and enabled state untouched. Vim reset retains the
navigation switch. Recorders for the reset scope are cancelled. Individual key
reset buttons remain available. Category resets now show a bottom toast for five
seconds; clicking it restores the previous overrides and global enabled state.
Only the latest reset is undoable. Editing the reset scope or closing Settings
discards that undo opportunity; unrelated edits are preserved. No app package generated. Details and validation:
docs/research/shortcut-category-reset.md.
