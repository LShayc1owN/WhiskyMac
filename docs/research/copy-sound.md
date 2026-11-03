# Copy feedback (2026-11-02, source only)

Two initially disabled switches control successful ordinary capture and explicit
history copy. Paste is silent, including card paste, plain/converted paste,
keyboard shortcuts and stack paste. Sensitive captures/exports remain silent;
automatic feedback is muted during any Privacy Mode. Explicit Settings audition
is allowed. Volume defaults to 35%, with a shared 120ms playback interval.

## Audio selection and licensing

User selected Kenney UI Audio: https://kenney.nl/assets/ui-audio (CC0).
Bundled samples: click1.wav, click2.wav, click4.wav; the fresh preference defaults
to Kenney Click 4. Existing sound preferences are preserved. Runtime macOS
Pop/Tink/Glass remain available. No Apple audio files are redistributed.

The official ZIP returned HTTP 403. Downloaded the WAV mirror from
https://github.com/Calinou/kenney-ui-audio at revision
8c3d81b9159d058c444f89d12d518276b0b09345. Its original CC0 license and source
notice are preserved in docs/licenses. Files are only renamed with a kenney-
prefix; the mirror documents conversion from OGG to WAV. Three small files are
loaded lazily through AppResources; no code dependencies or background polling.

## Implementation

- App/CopySound.swift: preferences, bounded output, lazy NSSound loading and
  injectable clock/output. Missing assets/output failures stay silent.
- GeneralSettings.swift: persistence in the independent defaults domain.
- CaptureClipboardChange: didRecord only after an admitted ordinary capture is
  saved; exclusions, sensitive sources, failed saves and paused capture are silent.
  Repeated ordinary captures can notify even if content deduplication reuses a row.
- AppKitPasteboard: didWrite once after successful explicit copy; writeForPaste
  and writeSensitive suppress notifications. No payload reaches the audio player.
- SelectItem, ClipboardController and PanelWiring: carry paste intent across
  card, plain, transform, keyboard and stack paths. Explicit copy stays audible.
- AppDelegate: wires current preferences/privacy, stops playback on protection
  entry and termination. Settings support selection, volume and audition in EN,
  FR and Simplified Chinese.

## Validation

CopySoundTests use simulated playback and a private synthetic pasteboard; verify
preferences/corrupt data, privacy/event gating, bounded volume, rate limiting,
failed saves/output, exclusions, sensitivity, pause, successful writes and all
six sound resources without playing audio. A routing regression checks seven
paste paths stay silent and both explicit-copy routes notify.
Full regression: evidence/2026-11-02/copy-only-sound-tests.log.

Listening quality and output-device behavior await user audition. No application
package, installer or distribution ZIP was generated.
