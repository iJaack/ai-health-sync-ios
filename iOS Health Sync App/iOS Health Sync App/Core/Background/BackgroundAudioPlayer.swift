// Copyright 2026 Marcus Neves
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import os

/// Plays an inaudible audio loop to prevent iOS from suspending the app while the server is active.
///
/// iOS aggressively suspends apps that move to the background (~30 seconds).
/// The `audio` UIBackgroundMode combined with an active AVAudioSession keeps the app alive.
/// The generated tone is a 0.1s silence at minimum sample rate — effectively zero battery impact.
///
/// Lifecycle:
/// - Call `start()` when the server is running AND the app enters background
/// - Call `stop()` when the server stops OR the app returns to foreground
/// - Stopping releases the audio session so other apps can use audio normally
@MainActor
final class BackgroundAudioPlayer {
    private var audioPlayer: AVAudioPlayer?
    private(set) var isPlaying = false

    func start() {
        guard !isPlaying else { return }

        do {
            // Configure audio session for background playback
            // .playback category keeps the app alive; mixWithOthers avoids interrupting music/podcasts
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            // Generate a minimal silent WAV in memory (no bundled file needed)
            let wavData = Self.generateSilentWAV(durationSeconds: 1.0, sampleRate: 8000)
            let player = try AVAudioPlayer(data: wavData)
            player.numberOfLoops = -1  // Loop forever
            player.volume = 0.0        // Completely silent
            player.play()

            audioPlayer = player
            isPlaying = true
            AppLoggers.app.info("Background audio started — app will stay alive in background")
        } catch {
            AppLoggers.app.error("Failed to start background audio: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        guard isPlaying else { return }

        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false

        // Deactivate audio session so other apps can reclaim audio
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Not critical — session will be cleaned up naturally
            AppLoggers.app.info("Audio session deactivation note: \(error.localizedDescription, privacy: .public)")
        }
        AppLoggers.app.info("Background audio stopped")
    }

    /// Generates a minimal WAV file containing silence.
    /// 8kHz mono 16-bit PCM, 1 second = 16KB. Tiny and efficient.
    private static func generateSilentWAV(durationSeconds: Double, sampleRate: Int) -> Data {
        let numChannels: Int = 1
        let bitsPerSample: Int = 16
        let bytesPerSample = bitsPerSample / 8
        let numSamples = Int(durationSeconds * Double(sampleRate))
        let dataSize = numSamples * numChannels * bytesPerSample
        let fileSize = 36 + dataSize  // Header (44) - 8 bytes for RIFF header itself

        var wav = Data()

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Array($0) })
        wav.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        wav.append(contentsOf: "fmt ".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })       // Chunk size
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })        // PCM format
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(numChannels).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        let byteRate = sampleRate * numChannels * bytesPerSample
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(byteRate).littleEndian) { Array($0) })
        let blockAlign = numChannels * bytesPerSample
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(blockAlign).littleEndian) { Array($0) })
        wav.append(contentsOf: withUnsafeBytes(of: UInt16(bitsPerSample).littleEndian) { Array($0) })

        // data chunk (all zeros = silence)
        wav.append(contentsOf: "data".utf8)
        wav.append(contentsOf: withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Array($0) })
        wav.append(Data(count: dataSize))

        return wav
    }
}
