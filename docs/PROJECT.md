# Project scope and maintenance plan

Current as of 2026-11-18. WhiskyMac is an independent macOS clipboard manager
based on Whisk v1.0.3. The product should make locally captured content easy to
find and reuse while keeping sensitive content separate and expensive preview
work bounded. It targets macOS 15 and later, uses public system APIs, and has no
third-party Swift package dependencies.

Use this document for current scope and the next maintenance work,
[ARCHITECTURE.md](ARCHITECTURE.md) for dependency boundaries,
[DEVELOPMENT.md](DEVELOPMENT.md) for build and runtime details, and
[CHANGELOG.md](../CHANGELOG.md) for historical changes. Local research and
acceptance records describe particular iterations; their old defaults and
"source only" labels are not a current feature specification.

## Responsibilities

| Location | Responsibility |
| --- | --- |
| `Sources/Whisk/Entities` | History invariants, content references, rich-text grouping, pins, interaction and retention values. |
| `Sources/Whisk/UseCases` | Capture, selection, filtering, editing, splitting, retention and undo operations through Foundation-only ports. |
| `Sources/Whisk/Adapters/Controllers` | History state, search, selection, facets and the single callback-based polling entry point. |
| `Sources/Whisk/Adapters/Presenters` | Display DTOs, excerpts, labels, search highlights and bounded presentation caches. |
| `Sources/Whisk/Adapters/Gateways` | Pasteboard service reads, SQLite persistence, deferred binary reads, legacy import and storage fallback. |
| `Sources/Whisk/App/Composition` and `AppDelegate` | Identity, distribution policy, dependency assembly and lifecycle wiring. |
| `Sources/Whisk/App/Panel` | Windows, keyboard routing, observable view state, guarded `PanelActions` and split sessions. |
| `Sources/Whisk/App/Privacy` | Manual/automatic protection, the public sharing detector and expiring sensitive sessions. |
| `Sources/Whisk/App/Settings`, `App/Presentation` | Persisted preferences, shared viewport, onboarding and preview services. |
| `Sources/Whisk/App/UI`, `Components` | Independent macOS 15 and macOS 26 renderers, factory contracts and reusable primitives. |
| `Sources/Whisk/Resources`, `Assets`, `Packaging` | Generated translations, runtime assets, editable artwork and distribution metadata. |
| `Tests/WhiskTests` | Behavior, persistence contracts, privacy isolation, resource bounds and offscreen framework regressions. |
| `scripts`, `.github/workflows` | Build, resource generation, verification and guarded distribution workflows. |
| `docs` | Maintainer documentation, website, listing content and asset license evidence. |

## Product contracts

| Area | Required behavior |
| --- | --- |
| Capture and history | Record text, rich text, links, images and file references. Compare payload and original RTF for duplicates; group matching rich-text bodies while keeping plain copies independent. Default capacity is 500 unpinned entries; pins are exempt from capacity and age eviction. |
| Reuse and navigation | Preserve copy, direct/plain paste, transforms, drag, full previews, editing, paste stack, keyboard and optional Vim navigation. Global shortcuts start disabled; direct paste requires the relevant macOS permission. |
| Pins | Keep notes, seven tags and persistent content masking. Support aggregated history and a separate workspace, defaulting to a list near the pointer. Explicit copy/paste still exports original content. |
| Splitting | Review line, paragraph, separator or HTTP(S)-link results before saving. Keep/add, replace and grouped saves are atomic and undoable; capacity eviction needs confirmation. Groups preserve source pin policy and choose original or ordered parts before export. |
| Privacy display | Mask raw content and accessibility output; clear drafts and preview state. Search, app labels and filters have separate permissions. App filters default on while protected; search, card source labels and other filters default off. Manual pointer reveal is local and visible to a recording too. Explicit privacy copy/paste follows the separate interaction profile; full preview, edit and split stay blocked. |
| Sharing detection | Opt-in, limited to supported Zoom/Teams toolbar titles through public Accessibility APIs. The application starts in normal mode; an observed sharing event latches automatic protection. Uncertain observations cannot release that latch; release requires two scoped-clear observations stable for five seconds. Automatic changes cannot clear manual protection. |
| Sensitive capture | Excluded applications are never recorded. Sensitive applications go directly to a separate memory-only store, with no extra enable switch. Retention is 1–1440 minutes, default 2; at most 10 entries / 16 MiB, with a ten-second explicit reveal. Expiry, app-rule changes and lifecycle cleanup remove entries without undo or recovery. Concealed/transient/generated markers always prevent capture. |
| Performance | Load a validated lightweight history snapshot once. Keep image/RTF originals behind immutable disk references; read them only for mounted previews or explicit content operations. Bound caches and workers, invalidate stale callbacks, and release panel hosts and content caches on close/protection. Cache budgets do not establish a total process-memory limit. |
| Settings and resources | Support seven languages, normal/privacy interaction profiles, continuous card sizes, settings search, opt-in audio and category shortcut reset with Undo. Keep one string catalog and generate all language resources from it. Paste and sensitive/protected feedback remain silent. |
| Network and distribution | Link previews and launch-time update checks start off. Manual and opt-in launch checks use the selected Release, Beta, or combined channel. Release is the default. Automatic attempts are limited to once per channel every 24 hours. App Store builds omit external update checks. Public release locations and signing are configured separately. |

## Compatibility that remains necessary

- Keep the `Whisk` Swift module/executable and its resource-bundle name. The
  application identity is `dev.whisky.maclx`; the existing development data
  directory and test override are documented in DEVELOPMENT.md.
- Keep the JSON-to-SQLite import and transactional conversion of old inline
  image/RTF rows to immutable binary revisions. They protect existing history
  and undo references. Only files in WhiskyMac's selected data directory are
  imported; upstream Whisk data is not discovered or imported automatically.
- Keep the small mappings for saved card-size presets and interaction
  preferences. Obsolete preset UI types and translations are unnecessary for
  reading those preferences.
- Keep volatile storage and corrupt-database recovery. Storage failures must
  leave the session usable and failed imports retryable.
- Keep source artwork alongside the compiled symbol bundle, and runtime assets
  alongside website assets when both consumers need them. Preserve upstream
  history, notices, licenses and additional permissions.
- Keep App Store and Developer ID scripts: they implement distribution paths
  covered by the project. Empty public release URLs intentionally prevent
  publication until the corresponding configuration is ready.

## Maintenance order

1. **Make full verification reliable.** Preserve the 90% coverage gate and the
   existing assertions. Investigate native text pixel comparisons, Quick Look
   completion and sharing-monitor timer waits under a busy main run loop;
   prefer controllable scheduling for lifecycle tests while retaining
   real-system integration checks. Compare
   full-suite results with focused Debug/Release runs before attributing a
   failure to a code change.
2. **Complete real-system acceptance.** Exercise supported Zoom/Teams versions
   and languages, Handoff attribution, VoiceOver, focus restoration, direct
   paste, shortcut recording, audio coexistence and repeated panel teardown.
   Synthetic/offscreen tests alone do not establish those results. Measure
   memory and latency with a stated dataset and build.
3. **Reduce active responsibility hotspots incrementally.** SettingsView still
   owns many feature sections and AppDelegate assembles several lifecycles.
   Extract cohesive sections/wiring with existing rendering and privacy tests
   preserving behavior. These are active implementations, so changes need
   behavior evidence rather than deletion based on file length.
4. **Prepare distribution when requested.** Set and verify the project's public
   source/support/privacy URLs, review corresponding-source assets and notices,
   then validate signing and isolated packaged startup. Generate packages and
   perform remote publication only as part of an explicit distribution task.

For each future cleanup, establish the call path and resource consumer first.
Remove the obsolete implementation, update tests to exercise the actual runtime
path, regenerate affected resources, and run the documented checks. Keep current
product contracts here instead of adding another accumulating iteration plan.
