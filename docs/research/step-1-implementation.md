# WhiskyMac: first implementation step

Date: 2026-10-31. Based on Whisk v1.0.3 at
`1ebcee1e0735e957777c599017ee411d8046c7e7` (255 ancestor commits).
Local branch: `may/v1.0.3`. No remote is configured and no commit was made.

The development app uses `dev.whisky.maclx` and **WhiskyMac**. Its history
directory is `~/Library/Application Support/WhiskMay-Dev`, with
`WHISK_MAY_DATA_DIR` for synthetic tests. Its settings suite is
`dev.whisky.maclx`. The original `WHISK_DATA_DIR` and original settings domain
are not read. The May directory can still migrate its own old JSON history.

Both global shortcuts start disabled, independently. A user can enable each
in Settings or record a new binding, which enables that shortcut. Update
checks are disabled at the distribution level and link previews default off.
Login item registration remains user initiated. The development package uses
the default macOS app icon while the upstream brand icon stays in source.

Validation:

- `swift build --disable-sandbox`: passed.
- `./scripts/check-dependency-rule.sh`: passed.
- `swift format lint --strict --recursive Sources Tests Package.swift`: passed.
- Synthetic isolation and related tests: 33 passed, including the assertion
  that the original environment override is ignored. Log:
  `docs/research/evidence/2026-10-31/isolation-tests.log`.
- Full test suite with macOS system services available: 312 tests, 51 suites,
  5 failed tests and 6 issues. These are the same upstream singular/plural
  localization and two SwiftUI layout failures documented in the first audit.
  Log: `docs/research/evidence/2026-10-31/full-tests-unsandboxed.log`.
- Full test suite inside the workspace sandbox also encounters system-service
  failures. Log: `docs/research/evidence/2026-10-31/full-tests.log`.
- `scripts/build-app.sh 0.0.0 native`: passed. The ZIP was extracted, its
  ad-hoc signature verified strictly, its Info.plist checked for identity
  and macOS 15.0 minimum, and its resource bundle checked. The executable's
  Mach-O minimum is also macOS 15.0.

The distributable artifact is `dist/WhiskyMac.zip`. The unpacked app in
the Desktop-backed workspace can acquire Finder metadata that interferes
with strict code-sign verification; the app extracted from the ZIP verifies.
After the first handoff, the user observed that the app exited immediately.
The crash report showed `AppIdentity.defaults` trapping because
`UserDefaults(suiteName:)` was called with the app's own bundle identifier.
The packaged app now uses `.standard` for its own domain; the bare SwiftPM
executable uses the explicit May suite. Version 0.0.1 was built, extracted,
and smoke tested with a temporary history directory. Its runtime bundle ID
was `dev.whisky.maclx`, and no clipboard polling ran. Side-by-side UI and
permission behavior still require observation on the user's Mac.

The inherited release, DMG, and App Store packaging scripts and metadata
still describe upstream Whisk. They are outside this local development
package and require separate work before public distribution.
