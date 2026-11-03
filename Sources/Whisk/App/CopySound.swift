// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AppKit
import Foundation

/// CC0 Kenney samples plus runtime references to system sounds; no Apple audio is bundled.
enum CopySound: String, CaseIterable, Codable, Identifiable {
    case kenneyClick1 = "Kenney Click 1", kenneyClick2 = "Kenney Click 2", kenneyClick4 = "Kenney Click 4"
    case pop = "Pop", tink = "Tink", glass = "Glass"
    var id: String { rawValue }

    func load() -> NSSound? {
        let filename: String
        switch self {
        case .kenneyClick1: filename = "kenney-click1"
        case .kenneyClick2: filename = "kenney-click2"
        case .kenneyClick4: filename = "kenney-click4"
        case .pop, .tink, .glass: return NSSound(named: NSSound.Name(rawValue))
        }
        guard
            let url = AppResources.bundle.url(forResource: filename, withExtension: "wav")
                ?? AppResources.bundle.url(forResource: filename, withExtension: "wav", subdirectory: "Sounds")
        else { return nil }
        return NSSound(contentsOf: url, byReference: false)
    }
}

struct CopySoundPreferences: Codable, Equatable {
    var onCapture = false
    var onHistoryCopy = false
    var sound = CopySound.kenneyClick4
    var volume: Float = 0.35

    var safeVolume: Float { volume.isFinite ? min(1, max(0, volume)) : 0.35 }
}

/// Shared, bounded output and rate limit. No payload, per-item identity, network,
/// timers or disk writes are needed for audible feedback.
final class CopySoundPlayer {
    enum Event { case captured, historyCopy }
    typealias Output = (CopySound, Float) -> Bool
    private let output: Output
    private let stopOutput: () -> Void
    private let now: () -> TimeInterval
    private var lastPlayed: TimeInterval?
    static let minimumInterval: TimeInterval = 0.12

    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        output: Output? = nil, stopOutput: (() -> Void)? = nil
    ) {
        self.now = now
        let system = SystemSoundOutput()
        self.output = output ?? { system.play($0, volume: $1) }
        self.stopOutput = stopOutput ?? { system.stop() }
    }

    @discardableResult
    func play(_ event: Event, preferences: CopySoundPreferences, protected: Bool) -> Bool {
        guard !protected else { return false }
        switch event {
        case .captured: guard preferences.onCapture else { return false }
        case .historyCopy: guard preferences.onHistoryCopy else { return false }
        }
        return emit(preferences)
    }

    /// Explicit audition is available even when automatic feedback is off.
    @discardableResult
    func preview(_ preferences: CopySoundPreferences) -> Bool { emit(preferences) }

    func stop() { stopOutput() }

    private func emit(_ preferences: CopySoundPreferences) -> Bool {
        guard preferences.safeVolume > 0 else { return false }
        let instant = now()
        if let lastPlayed, instant - lastPlayed < Self.minimumInterval { return false }
        guard output(preferences.sound, preferences.safeVolume) else { return false }
        lastPlayed = instant
        return true
    }
}

private final class SystemSoundOutput {
    private var sounds: [CopySound: NSSound] = [:]
    private var current: NSSound?

    func play(_ choice: CopySound, volume: Float) -> Bool {
        if sounds[choice] == nil {
            sounds[choice] = choice.load()
        }
        guard let sound = sounds[choice] else { return false }
        current?.stop()
        sound.volume = volume
        current = sound
        return sound.play()
    }

    func stop() { current?.stop(); current = nil }
    deinit { current?.stop() }
}
