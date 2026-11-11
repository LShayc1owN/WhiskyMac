// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import CryptoKit
import Testing

@testable import Whisk

@MainActor
@Suite struct CopySoundFeedback {
    private final class Playback: CopySoundPlayback {
        var starts = 0
        var stops = 0
        var succeeds = true
        func start() -> Bool { starts += 1; return succeeds }
        func stop() { stops += 1 }
    }

    @Test func decoded_samples_are_cached_but_playback_is_disposed_on_finish_or_replace() throws {
        let sample = try #require(CopySound.kenneyClick4.load())
        var loads = 0
        var players: [Playback] = []
        var completions: [() -> Void] = []
        var volumes: [Float] = []
        let output = CopySoundAudioOutput(
            load: { _ in
                loads += 1; return sample
            },
            factory: { _, volume, finish in
                let player = Playback()
                players.append(player)
                completions.append(finish)
                volumes.append(volume)
                return player
            })
        #expect(!output.play(.kenneyClick1, volume: 0))
        #expect(!output.play(.kenneyClick1, volume: .nan))
        #expect(loads == 0)
        #expect(output.play(.kenneyClick1, volume: 0.2))
        #expect(output.play(.kenneyClick1, volume: 0.4))
        #expect(loads == 1 && players[0].stops == 1)
        completions[0]()
        #expect(players[1].stops == 0)
        completions[1]()
        #expect(players[1].stops == 1)
        #expect(output.play(.tink, volume: 2))
        #expect(loads == 2 && volumes == [0.2, 0.4, 1])
        output.stop()
        #expect(players[2].stops == 1)
        completions[2]()
        #expect(players[2].stops == 1)
    }

    @Test func missing_assets_and_failed_devices_stay_silent_and_teardown_stops_playback() throws {
        let sample = try #require(CopySound.kenneyClick4.load())
        let missing = CopySoundAudioOutput(
            load: { _ in nil },
            factory: { _, _, _ in
                Issue.record("No device should be opened without audio"); return nil
            })
        #expect(!missing.play(.pop, volume: 1))
        let unavailable = CopySoundAudioOutput(load: { _ in sample }, factory: { _, _, _ in nil })
        #expect(!unavailable.play(.pop, volume: 1))
        let failed = Playback()
        failed.succeeds = false
        let output = CopySoundAudioOutput(load: { _ in sample }, factory: { _, _, _ in failed })
        #expect(!output.play(.pop, volume: 1))
        #expect(failed.stops == 1)
        let active = Playback()
        var owner: CopySoundAudioOutput? = CopySoundAudioOutput(load: { _ in sample }, factory: { _, _, _ in active })
        #expect(owner?.play(.pop, volume: 1) == true)
        owner = nil
        #expect(active.stops == 1)
        #expect(CopySoundPCM.load(URL(fileURLWithPath: "/nonexistent-sound.wav")) == nil)
    }

    @Test func sound_preferences_start_silent_and_persist_in_the_own_domain() throws {
        let sandbox = try IsolatedDefaults()
        let settings = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(!settings.copySound.onCapture && !settings.copySound.onHistoryCopy)
        settings.copySound.onCapture = true
        settings.copySound.sound = .tink
        settings.copySound.volume = 0.2
        let restored = GeneralSettingsStore(defaults: sandbox.defaults)
        #expect(restored.copySound == settings.copySound)
        #expect(!restored.copySound.onHistoryCopy)
        sandbox.defaults.set(Data([0]), forKey: "copySound")
        #expect(GeneralSettingsStore(defaults: sandbox.defaults).copySound == CopySoundPreferences())
    }

    @Test func event_switches_and_privacy_gate_run_before_loading_or_playing_audio() {
        var calls: [(CopySound, Float)] = []
        let player = CopySoundPlayer(
            now: { 0 },
            output: {
                calls.append(($0, $1)); return true
            })
        var settings = CopySoundPreferences()
        #expect(!player.play(.captured, preferences: settings, protected: false))
        #expect(!player.play(.historyCopy, preferences: settings, protected: false))
        settings.onCapture = true
        settings.onHistoryCopy = true
        #expect(!player.play(.captured, preferences: settings, protected: true))
        #expect(!player.play(.historyCopy, preferences: settings, protected: true))
        #expect(calls.isEmpty)
        #expect(player.play(.historyCopy, preferences: settings, protected: false))
        #expect(calls.count == 1)
        #expect(calls[0].0 == .kenneyClick4 && calls[0].1 == 0.35)
    }

    @Test func fast_events_do_not_stack_and_preview_is_explicit() {
        var time: TimeInterval = 0
        var plays = 0
        var stops = 0
        let player = CopySoundPlayer(
            now: { time },
            output: { _, _ in
                plays += 1; return true
            },
            stopOutput: { stops += 1 })
        var settings = CopySoundPreferences()
        #expect(player.preview(settings))  // Explicit audition works while both feedback switches are off.
        #expect(!player.preview(settings))
        settings.onCapture = true
        settings.onHistoryCopy = true
        time = 0.1
        #expect(!player.play(.captured, preferences: settings, protected: false))
        time = 0.13
        #expect(player.play(.captured, preferences: settings, protected: false))
        #expect(!player.play(.historyCopy, preferences: settings, protected: false))
        #expect(plays == 2)
        player.stop()
        #expect(stops == 1)
    }

    @Test func zero_volume_and_missing_output_stay_silent_and_volume_is_bounded() {
        var settings = CopySoundPreferences()
        var volumes: [Float] = []
        let player = CopySoundPlayer(
            now: { 0 },
            output: { _, volume in
                volumes.append(volume); return false
            })
        settings.volume = 0
        #expect(!player.preview(settings))
        #expect(volumes.isEmpty)
        settings.volume = 2
        #expect(!player.preview(settings))
        settings.volume = .nan
        #expect(!player.preview(settings))
        #expect(volumes == [1, 0.35])
        settings.volume = -1
        #expect(settings.safeVolume == 0)
    }

    @Test func record_feedback_requires_admitted_and_saved_content() throws {
        let board = ScriptedPasteboard()
        let disk = InMemoryHistoryStore()
        let capture = CaptureClipboardChange(pasteboard: board, clock: FakeClock(), store: disk)
        var records = 0
        _ = try capture(into: History(), didRecord: { records += 1 })
        #expect(records == 0)
        let snapshot = PasteboardSnapshot(
            payload: .text("synthetic"), source: SourceApp(name: "Test", bundleID: "test.app"))
        board.pendingSnapshots = [snapshot, snapshot, snapshot]
        _ = try capture(into: History(), excluding: ["test.app"], didRecord: { records += 1 })
        _ = try capture(into: History(), sensitiveBundleIDs: ["test.app"], didRecord: { records += 1 })
        #expect(records == 0)
        _ = try capture(into: History(), didRecord: { records += 1 })
        #expect(records == 1)
        board.pendingSnapshots = [snapshot]
        let failed = CaptureClipboardChange(pasteboard: board, clock: FakeClock(), store: FailingHistoryStore())
        #expect(throws: HistoryStoreError.self) {
            _ = try failed(into: History(), didRecord: { records += 1 })
        }
        #expect(records == 1)
    }

    @Test func controller_pause_skips_capture_feedback() {
        let board = ScriptedPasteboard()
        let controller = ClipboardController(
            pasteboard: board, store: InMemoryHistoryStore(), clock: FakeClock(),
            logger: RecordingLogger(), present: { _ in })
        var records = 0
        controller.didRecord = { records += 1 }
        controller.setPaused(true)
        board.pendingSnapshots = [PasteboardSnapshot(payload: .text("paused"), source: nil)]
        controller.pollTick()
        controller.setPaused(false)
        controller.pollTick()
        #expect(records == 0)
        board.pendingSnapshots = [PasteboardSnapshot(payload: .text("recorded"), source: nil)]
        controller.pollTick()
        #expect(records == 1)
    }

    @Test func history_write_notifies_once_and_sensitive_exports_are_silent() {
        let board = NSPasteboard(name: NSPasteboard.Name("sound-tests-\(UUID())"))
        defer { board.releaseGlobally() }
        var writes = 0
        let gateway = AppKitPasteboard(board: board, didWrite: { writes += 1 })
        gateway.write(.text("synthetic"), rtf: nil)
        #expect(writes == 1)
        #expect(gateway.readIfChanged() == nil)
        gateway.writeSensitive(.text("synthetic secret"), rtf: nil)
        #expect(writes == 1)
        #expect(gateway.readIfChanged() == nil)
    }

    @Test func paste_routes_stay_silent_while_explicit_copies_notify() {
        let board = NSPasteboard(name: NSPasteboard.Name("sound-routing-\(UUID())"))
        defer { board.releaseGlobally() }
        var copies = 0
        let gateway = AppKitPasteboard(board: board, didWrite: { copies += 1 })
        let disk = InMemoryHistoryStore()
        let item = anItem(.text("synthetic"))
        disk.stored = [item]
        let controller = ClipboardController(
            pasteboard: gateway, store: disk, clock: FakeClock(),
            logger: RecordingLogger(), present: { _ in })
        let scheduler = HandCrankedScheduler()
        let actions = PanelWiring.actions(
            for: controller, searchDebounce: Debouncer(delay: 0.18, scheduler: scheduler.schedule),
            hidePanel: {}, paste: {}, dragBegan: {},
            system: .init(
                openLink: { _ in }, revealFiles: { _ in }, saveToDisk: { _ in },
                excludeSource: { _, _ in }, beginEditing: { _ in }, openPasteboardSettings: {}))
        actions.select(item.id)
        actions.selectPlain(item.id)
        actions.transform(item.id, .uppercase)
        actions.activate()
        actions.activatePlain()
        actions.activateCard(0)
        controller.toggleStack(item.id)
        #expect(controller.popStack())
        #expect(copies == 0)
        #expect(board.string(forType: .string) == "synthetic")
        actions.copy(item.id)
        #expect(copies == 1)
        actions.copySelected()
        #expect(copies == 2)
        #expect(gateway.readIfChanged() == nil)
    }

    @Test func selectable_sounds_load_from_bundled_or_system_resources() throws {
        var decodedBytes = 0
        for sound in CopySound.allCases {
            #expect(sound.id == sound.rawValue)
            #expect(!sound.label.isEmpty)
            let restored = try JSONDecoder().decode(CopySound.self, from: JSONEncoder().encode(sound))
            #expect(restored == sound)
            let sample = try #require(sound.load())  // Decode only; never open audio output in tests.
            decodedBytes += sample.bytes.count
            #expect(!sample.bytes.isEmpty)
            #expect(sample.format.mChannelsPerFrame == 1 || sample.format.mChannelsPerFrame == 2)
            #expect(sample.format.mBytesPerFrame == sample.format.mChannelsPerFrame * 4)
            #expect(sample.bytes.count % Int(sample.format.mBytesPerFrame) == 0)
            if sound.bundledFilename != nil {
                let frames = sample.bytes.count / Int(sample.format.mBytesPerFrame)
                #expect(Double(frames) / sample.format.mSampleRate < 0.5)
            }
        }
        // Auditioning the complete menu must keep the existing sample cache small.
        #expect(decodedBytes < 2 * 1024 * 1024)
        let groups = CopySound.Collection.allCases.flatMap(\.sounds)
        #expect(groups.count == Set(groups).count)
        #expect(Set(groups) == Set(CopySound.allCases))
        #expect(CopySound.Collection.allCases.allSatisfy { $0.id == $0.rawValue })
    }

    @Test func new_audio_bytes_match_the_pinned_upstream_assets() throws {
        struct Asset: Decodable {
            let target: String
            let sha256: String
            let bytes: Int
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let manifest = root.appendingPathComponent("docs/licenses/copy-sound-assets.json")
        let assets = try JSONDecoder().decode([Asset].self, from: Data(contentsOf: manifest))
        var seen = Set<String>()
        for asset in assets {
            let file = root.appendingPathComponent("Sources/Whisk/Resources/Sounds/\(asset.target)")
            let data = try Data(contentsOf: file)
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(hash == asset.sha256)
            #expect(seen.insert(hash).inserted)
            #expect(data.count == asset.bytes)
            #expect(
                CopySound.allCases.contains { $0.bundledFilename == file.deletingPathExtension().lastPathComponent })
        }
        #expect(assets.reduce(0) { $0 + $1.bytes } < 128 * 1024)
    }
}
