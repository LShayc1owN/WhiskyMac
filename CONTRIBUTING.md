# Contributing to WhiskyMac

Thanks for helping! WhiskyMac is based on Whisk — this page
is everything you need to get a green PR on the first try.

## Setup

```sh
# From your local WhiskyMac checkout:
swift run Whisk
```

**Toolchain:** building needs the macOS 26 SDK (Xcode 26+, or the matching
Command Line Tools). `swift build` works with Command Line Tools alone, but
**`swift test` requires a full Xcode installation** — if you only have CLT,
push your branch and let CI run the suite (it runs on every push).

Useful entry points while developing:

```sh
swift run Whisk --show-panel      # open the history panel immediately
swift run Whisk --show-settings   # open the Settings window immediately
./scripts/build-app.sh 0.0.0 native   # package a real Whisk.app into dist/
```

## Before you push

CI runs exactly these, in this order — run them locally first:

```sh
./scripts/check-dependency-rule.sh
swift format lint --strict --recursive Sources Tests Package.swift
./scripts/localizations.sh check
swift build
swift test        # needs Xcode; otherwise let CI run it
```

`swift format format --in-place --recursive Sources Tests` fixes most lint
complaints automatically.

## Architecture in one minute

Whisk follows Clean Architecture inside a single module — the rings are
folders, and the Dependency Rule (source dependencies only point inward) is
enforced by `scripts/check-dependency-rule.sh`:

| Ring | Folder | May import |
|---|---|---|
| Entities | `Sources/Whisk/Entities/` | Foundation |
| Use cases | `Sources/Whisk/UseCases/` (+ `Ports/`) | Foundation |
| Interface adapters | `Sources/Whisk/Adapters/{Controllers,Presenters,Gateways}/` | Foundation (Gateways may also use AppKit + SQLite3) |
| Frameworks & drivers | `Sources/Whisk/App/` | anything |

Ground rules:

- **Views are dumb.** They render the presenter's `HistoryViewState`
  verbatim. Every display decision — labels, relative times, previews —
  belongs to the presenter.
- **The kernel is pure and synchronous.** Time comes in as a value
  (`Clock` port), the pasteboard and storage sit behind ports.
- **Fail closed.** No force-unwraps in production paths; a storage failure
  must never take the UI down.
- Full rules with diagrams: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
  ([français](docs/fr/ARCHITECTURE.md)).

## Tests

TDD is the house style: write the failing test first. Conventions:

- Test names state behaviour:
  `a_duplicate_copy_moves_the_existing_item_to_the_front`, never `testFoo1`.
- Deterministic always — frozen clocks, scripted pasteboards, temporary
  directories. No sleeps, no real pasteboard, no network.
- A port gets a **contract suite** that runs against every gateway
  implementing it (see `HistoryStoreContractTests`, parameterized over the
  SQLite and in-memory stores — a new gateway joins by adding a case).
- Views get **rendering tests**: draw them with `ImageRenderer` or host
  them in a window that is never ordered in (see `ViewRenderingTests`),
  one case per state the view can show. A test must never put a window
  on screen, register a hot key or touch the general pasteboard.
- `./scripts/coverage.sh` runs the suite with coverage and prints the
  per-file report CI archives. CI fails under 90 % line coverage of the
  testable code (everything but `AppDelegate`, `HotKey`, `PasteSimulator`
  and `main`); run it as `COVERAGE_MIN=90 ./scripts/coverage.sh` before
  pushing.

## User-facing strings

Every user-visible string goes through the `localized()` helper. Open
`Package.swift` in Xcode, then open
`Sources/Whisk/Resources/Localizable.xcstrings` in its String Catalog editor.
This catalog is the only translation source, with English keys and complete
English, French, German and Simplified Chinese translations. Entries are managed
manually because Xcode does not extract literals passed to our custom helper.
For counts, use the editor's **Vary by Plural** action: English, French and German
need One and Other; Chinese only needs Other. Keep format placeholders intact.

After changing the catalog, run:

```sh
./scripts/localizations.sh generate
./scripts/localizations.sh check
swift test
```

Commit the catalog and the generated `*.lproj/Localizable.strings` and
`.stringsdict` files together. Never edit those generated files by hand.
Generation and checking require full Xcode and its `xcstringstool`; regular
`swift build` uses the committed resources and needs no catalog compiler.
CI and app packaging reject stale generated resources. `LocalizationTests`
checks source coverage, translation states, placeholders, plural rules and
the compiled resources in all four languages. The interface follows macOS
language preferences unless overridden in Settings; unsupported languages fall back to English.

## Commits & PRs

- Code, comments and commit messages are in **English**; French docs mirror
  under `docs/fr/`.
- Prefix commit subjects with a [Gitmoji](https://gitmoji.dev): ✨ feature,
  🐛 fix, ♻️ refactor, ✅ tests, 📝 docs, 👷 CI, 🌐 i18n, 🔒 security…
- Keep PRs focused: one feature or fix per PR, with tests for behaviour
  changes.
- Anything a user would notice gets a line under `[Unreleased]` in
  [CHANGELOG.md](CHANGELOG.md); the release moves that section under the
  new version and its notes are taken from it.
- `main` is protected — all changes land through a PR with CI green.

## Reporting bugs & proposing features

Security flaws go through the private channel described in
[SECURITY.md](SECURITY.md), never through a public issue. Everyone taking
part is held to the [code of conduct](CODE_OF_CONDUCT.md).

Use the issue templates. For bugs, the macOS version and your keyboard
layout matter more often than you'd think (shortcuts are layout-aware).

## Licensing of contributions

Contributions to WhiskyMac are licensed under GPL-3.0-or-later. By submitting
a contribution, you grant the same App Store/TestFlight additional permission
for your contribution as set out in
[LICENSE-EXCEPTION-WHISKYMAC.md](LICENSE-EXCEPTION-WHISKYMAC.md), to the extent
you hold or can grant the relevant rights. You retain your copyright.

Confirm in your pull request that you have the right to submit the material
on these terms. Identify all third-party code and assets, their source and
licenses; do not represent third-party work as your own. Employer-owned work
requires the appropriate authorization. Upstream Whisk's original permission
is preserved separately in [LICENSE-EXCEPTION-APP-STORE.md](LICENSE-EXCEPTION-APP-STORE.md).
