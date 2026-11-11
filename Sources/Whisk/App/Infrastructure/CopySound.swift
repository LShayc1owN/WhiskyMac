// WhiskyMac: modified or added 2026-11-03 by LinShay (琳曦).
// SPDX-License-Identifier: GPL-3.0-or-later
// Upstream attribution: NOTICE. Additional permissions:
// LICENSE-EXCEPTION-APP-STORE.md and LICENSE-EXCEPTION-WHISKYMAC.md.

import AudioToolbox
import Foundation

/// CC0 Kenney/SFX Kit samples plus runtime system references; no Apple audio is bundled.
enum CopySound: String, CaseIterable, Codable, Identifiable {
    case kenneyClick1 = "Kenney Click 1", kenneyClick2 = "Kenney Click 2", kenneyClick3 = "Kenney Click 3"
    case kenneyClick4 = "Kenney Click 4", kenneyClick5 = "Kenney Click 5"
    case kenneyMousePress = "Kenney Mouse Press", kenneyMouseRelease = "Kenney Mouse Release"
    case kenneyRollover = "Kenney Rollover", kenneySwitch = "Kenney Switch"
    case sfxSoftButton = "SFX Soft Button", sfxSoftTap = "SFX Soft Tap"
    case sfxSoftSnap = "SFX Soft Snap", sfxBubble = "SFX Bubble"
    case pop = "Pop", tink = "Tink", glass = "Glass"
    var id: String { rawValue }

    enum Collection: String, CaseIterable, Identifiable {
        case kenney = "Kenney UI Audio", sfxKit = "SFX Kit", system = "macOS"
        var id: String { rawValue }
        var sounds: [CopySound] { CopySound.allCases.filter { $0.collection == self } }
    }

    var collection: Collection {
        if bundledFilename?.hasPrefix("kenney-") == true { return .kenney }
        return bundledFilename == nil ? .system : .sfxKit
    }

    var label: String {
        switch self {
        case .kenneyMousePress: localized("Mouse press")
        case .kenneyMouseRelease: localized("Mouse release")
        case .kenneyRollover: localized("Rollover tick")
        case .kenneySwitch: localized("Switch click")
        case .sfxSoftButton: localized("Soft button")
        case .sfxSoftTap: localized("Soft tap")
        case .sfxSoftSnap: localized("Soft snap")
        case .sfxBubble: localized("Small bubble")
        default: rawValue
        }
    }

    var bundledFilename: String? {
        switch self {
        case .kenneyClick1: "kenney-click1"
        case .kenneyClick2: "kenney-click2"
        case .kenneyClick3: "kenney-click3"
        case .kenneyClick4: "kenney-click4"
        case .kenneyClick5: "kenney-click5"
        case .kenneyMousePress: "kenney-mouseclick1"
        case .kenneyMouseRelease: "kenney-mouserelease1"
        case .kenneyRollover: "kenney-rollover2"
        case .kenneySwitch: "kenney-switch14"
        case .sfxSoftButton: "sfx-click-button-soft"
        case .sfxSoftTap: "sfx-click-tap-soft"
        case .sfxSoftSnap: "sfx-click-snap-soft"
        case .sfxBubble: "sfx-pop-small-bubble"
        case .pop, .tink, .glass: nil
        }
    }

    func load() -> CopySoundPCM? {
        guard let filename = bundledFilename else {
            return CopySoundPCM.load(URL(fileURLWithPath: "/System/Library/Sounds/\(rawValue).aiff"))
        }
        guard
            let url = AppResources.bundle.url(forResource: filename, withExtension: "wav")
                ?? AppResources.bundle.url(forResource: filename, withExtension: "wav", subdirectory: "Sounds")
        else { return nil }
        return CopySoundPCM.load(url)
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
        let system = CopySoundAudioOutput()
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

/// Small, decoded samples only; no open player/device is kept in the cache.
struct CopySoundPCM {
    let format: AudioStreamBasicDescription
    let bytes: Data

    static func load(_ url: URL) -> CopySoundPCM? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size <= 2 * 1024 * 1024
        else { return nil }
        var file: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(url as CFURL, &file) == noErr, let file else { return nil }
        defer { ExtAudioFileDispose(file) }
        var format = AudioStreamBasicDescription()
        var propertySize = UInt32(MemoryLayout.size(ofValue: format))
        guard ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &propertySize, &format) == noErr,
            format.mSampleRate.isFinite, (8000...192000).contains(format.mSampleRate),
            (1...2).contains(format.mChannelsPerFrame)
        else { return nil }
        var frames: Int64 = 0
        propertySize = UInt32(MemoryLayout.size(ofValue: frames))
        guard ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &propertySize, &frames) == noErr,
            frames > 0, Double(frames) <= format.mSampleRate * 5
        else { return nil }
        let channels = format.mChannelsPerFrame
        format = AudioStreamBasicDescription(
            mSampleRate: format.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: channels * 4, mFramesPerPacket: 1,
            mBytesPerFrame: channels * 4, mChannelsPerFrame: channels, mBitsPerChannel: 32, mReserved: 0)
        guard
            ExtAudioFileSetProperty(
                file, kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout.size(ofValue: format)), &format) == noErr
        else { return nil }
        var count = UInt32(frames)
        var bytes = Data(count: Int(count * format.mBytesPerFrame))
        let status = bytes.withUnsafeMutableBytes { raw in
            var buffers = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: channels, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
            return ExtAudioFileRead(file, &count, &buffers)
        }
        guard status == noErr, count > 0 else { return nil }
        bytes.count = Int(count * format.mBytesPerFrame)
        return CopySoundPCM(format: format, bytes: bytes)
    }
}

protocol CopySoundPlayback: AnyObject {
    func start() -> Bool
    func stop()
}

/// Main-thread lifecycle with an injectable device boundary. Completion releases
/// the queue; old completion callbacks cannot dispose a newer sound.
final class CopySoundAudioOutput {
    typealias Factory = (CopySoundPCM, Float, @escaping () -> Void) -> (any CopySoundPlayback)?
    private let load: (CopySound) -> CopySoundPCM?
    private let factory: Factory
    private var samples: [CopySound: CopySoundPCM] = [:]
    private var current: (any CopySoundPlayback)?
    private var generation = 0

    init(
        load: @escaping (CopySound) -> CopySoundPCM? = { $0.load() },
        factory: @escaping Factory = { AudioQueueCopyPlayback(sample: $0, volume: $1, finished: $2) }
    ) {
        self.load = load
        self.factory = factory
    }

    func play(_ choice: CopySound, volume: Float) -> Bool {
        guard volume.isFinite, volume > 0 else { return false }
        if samples[choice] == nil { samples[choice] = load(choice) }
        guard let sample = samples[choice] else { return false }
        stop()
        let token = generation
        current = factory(sample, min(1, volume)) { [weak self] in
            guard let self, self.generation == token else { return }
            self.stop()
        }
        guard current?.start() == true else { stop(); return false }
        return true
    }

    func stop() { generation += 1; current?.stop(); current = nil }
    deinit { current?.stop() }
}

private final class QueueCompletion {
    let finished: () -> Void
    init(_ finished: @escaping () -> Void) { self.finished = finished }
}

private func copySoundQueueStopped(
    _ userData: UnsafeMutableRawPointer?, _ queue: AudioQueueRef, _ property: AudioQueuePropertyID
) {
    guard let userData else { return }
    let completion = Unmanaged<QueueCompletion>.fromOpaque(userData).takeUnretainedValue()
    var running: UInt32 = 1
    var size = UInt32(MemoryLayout.size(ofValue: running))
    if AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &running, &size) == noErr, running == 0 {
        DispatchQueue.main.async(execute: completion.finished)
    }
}

/// AudioToolbox output only: no MusicKit, media session, Now Playing metadata,
/// remote command handlers, recording input, exclusive-device or ducking setup.
private final class AudioQueueCopyPlayback: CopySoundPlayback {
    private let sample: CopySoundPCM
    private let volume: Float
    private let completion: QueueCompletion
    private var queue: AudioQueueRef?

    init(sample: CopySoundPCM, volume: Float, finished: @escaping () -> Void) {
        self.sample = sample
        self.volume = volume
        self.completion = QueueCompletion(finished)
    }

    func start() -> Bool {
        var format = sample.format
        var output: AudioQueueRef?
        guard
            AudioQueueNewOutput(
                &format, { _, queue, _ in AudioQueueStop(queue, false) },
                nil, nil, nil, 0, &output) == noErr, let output
        else { return false }
        queue = output
        var buffer: AudioQueueBufferRef?
        let context = Unmanaged.passUnretained(completion).toOpaque()
        guard AudioQueueAllocateBuffer(output, UInt32(sample.bytes.count), &buffer) == noErr, let buffer,
            AudioQueueSetParameter(output, kAudioQueueParam_Volume, volume) == noErr,
            AudioQueueAddPropertyListener(output, kAudioQueueProperty_IsRunning, copySoundQueueStopped, context)
                == noErr
        else { stop(); return false }
        sample.bytes.withUnsafeBytes { raw in
            if let source = raw.baseAddress { buffer.pointee.mAudioData.copyMemory(from: source, byteCount: raw.count) }
        }
        buffer.pointee.mAudioDataByteSize = UInt32(sample.bytes.count)
        guard AudioQueueEnqueueBuffer(output, buffer, 0, nil) == noErr,
            AudioQueueStart(output, nil) == noErr
        else { stop(); return false }
        return true
    }

    func stop() {
        guard let queue else { return }
        self.queue = nil
        AudioQueueRemovePropertyListener(
            queue, kAudioQueueProperty_IsRunning,
            copySoundQueueStopped, Unmanaged.passUnretained(completion).toOpaque())
        // Dispose off the audio callback thread, synchronously. After this returns
        // AudioQueue no longer invokes callbacks; the completion context stays alive.
        withExtendedLifetime(completion) { AudioQueueDispose(queue, true) }
    }

    deinit { stop() }
}
