import Foundation
import AVFoundation
import Combine
import SwiftUI // Often needed for @MainActor and ObservableObject, though maybe implicit
// Assuming these types are part of the main WalkWrite module/target
// No explicit import needed if they are in the same target, but let's ensure clarity
// If these are in separate modules, specific imports would be needed.

// Import necessary types if they are not automatically available
// import WalkWrite // Explicit import removed as it's redundant within the same module

@MainActor
final class RecorderViewModel: ObservableObject {

    // MARK: - Published state
    @Published private(set) var isRecording = false
    @Published private(set) var isPaused = false
    @Published private(set) var permissionDenied = false
    @Published private(set) var isPreparingModel = false
    @Published private(set) var isProcessing = false
    @Published private(set) var finishedNote: Note?
    @Published private(set) var audioLevel: Float = 0.0
    @Published var transcriptionProgress: Double = 0.0 // New property for progress

    // MARK: - Private
    private var recorder: AVAudioRecorder?
    private var accumulatedTime: TimeInterval = 0
    private var currentSegmentStartTime: Date?
    private var timer: AnyCancellable?

    // Weak reference to persistent store so we can immediately persist raw audio
    private weak var store: NoteStore?

    func attachStore(_ store: NoteStore) {
        self.store = store
    }

    var elapsed: TimeInterval {
        accumulatedTime + (currentSegmentStartTime.map { Date().timeIntervalSince($0) } ?? 0)
    }

    // MARK: - Permissions
    @discardableResult
    func ensurePermission() async -> Bool {
        if await AVAudioApplication.requestRecordPermission() {
            permissionDenied = false
            return true
        } else {
            permissionDenied = true
            return false
        }
    }

    // MARK: - Recording control
    func startRecording() {
        guard !isRecording else { return } // Should not happen if UI logic is correct

        // No limits in open source version - upgrade is optional

#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
#endif

        let filename = ISO8601DateFormatter().string(from: .now) + ".wav"
        let url = AppFolders.notes.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false
        ]

        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.record()

        accumulatedTime = 0
        currentSegmentStartTime = .now
        isRecording = true
        isPaused = false

        startOrUpdateTimer()

        // Pre-warm WhisperEngine in the background
        // This will initialize the shared instance and load the model
        // if it hasn't been done yet for this app session.
        Task.detached(priority: .background) {
            Foundation.NSLog("RecorderViewModel: Pre-warming WhisperEngine...")
            _ = await WhisperEngine.shared // Access to initialize
            Foundation.NSLog("RecorderViewModel: WhisperEngine pre-warming initiated/completed.")
        }
    }

    private func startOrUpdateTimer() {
        timer?.cancel()
        timer = Timer.publish(every: 0.02, on: .main, in: .common) // Increased update rate for audio level
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isRecording && !self.isPaused {
                    self.recorder?.updateMeters()
                    // The power value is in dB, from -160 (silence) to 0 (max).
                    let power = self.recorder?.averagePower(forChannel: 0) ?? -160.0
                    // Normalize to 0.0 - 1.0.
                    // Adjusted range for better sensitivity to typical voice levels.
                    let minDb: Float = -45.0 // Quieter sounds will start showing activity sooner
                    let maxDb: Float = -10.0  // Louder sounds will hit max amplitude sooner
                    
                    var normalizedLevel: Float
                    if power < minDb {
                        normalizedLevel = 0.0
                    } else if power > maxDb {
                        normalizedLevel = 1.0
                    } else {
                        normalizedLevel = (power - minDb) / (maxDb - minDb)
                    }
                    
                    // Optional: Apply a curve to make it even more responsive at lower levels
                    // For example, a square root curve (power of 0.5)
                    // self.audioLevel = pow(normalizedLevel, 0.5)
                    self.audioLevel = normalizedLevel
                }
                self.objectWillChange.send() // For elapsed time and other UI updates
            }
    }

    func pauseRecording() {
        guard isRecording, !isPaused, let recorder = recorder, let segmentStartTime = currentSegmentStartTime else { return }
        recorder.pause()
        accumulatedTime += Date().timeIntervalSince(segmentStartTime)
        currentSegmentStartTime = nil
        isPaused = true
        audioLevel = 0.0 // Reset audio level on pause
        // Timer is not cancelled here if we want elapsed time to freeze but other UI might still update.
        // However, for audio level, it should stop. The current timer logic handles this via !self.isPaused check.
        // If timer is fully stopped: timer?.cancel()
        self.objectWillChange.send() // Ensure UI updates for isPaused state
    }

    func resumeRecording() {
        guard isRecording, isPaused, let recorder = recorder else { return }
        recorder.record() // AVAudioRecorder resumes with record()
        currentSegmentStartTime = .now
        isPaused = false
        startOrUpdateTimer() // Restart timer with metering
    }

    func stopRecording() {
        guard isRecording, let recorder = recorder else { return }
        audioLevel = 0.0 // Reset audio level on stop

        if !isPaused, let segmentStartTime = currentSegmentStartTime {
            accumulatedTime += Date().timeIntervalSince(segmentStartTime)
        }
        currentSegmentStartTime = nil

        recorder.stop()
        timer?.cancel()
        
        let duration = accumulatedTime // Use the accurately tracked accumulated time
        let audioURL = recorder.url
        
        self.recorder = nil
        self.isRecording = false
        self.isPaused = false
        self.accumulatedTime = 0

        // Immediately persist a placeholder note so the user never loses their recording
        let placeholder = Note(createdAt: Date(), // Explicit Date()
                               duration: duration,
                               audioURL: audioURL,
                               transcript: "",
                               words: [])
        let placeholderID = placeholder.id
        store?.add(placeholder)

        isPreparingModel = true

        // Run the heavy transcription work off the MainActor so that the UI
        // can update and show the "Preparing…" message while Core ML compiles
        // the encoder on first launch.
        Task.detached(priority: .userInitiated) { [weak self, audioURL, duration, placeholderID] in
            guard let self else { return }

            await MainActor.run {
                self.isProcessing = true
                self.transcriptionProgress = 0.0 // Reset progress
            }

            var transcript = ""
            var words: [WordStamp] = []

            do {
                // Assign to temporary local constants first
                let (localTranscript, localWords) = try await WhisperEngine.shared.transcribe(audioFileURL: audioURL) { progress in
                    Task { @MainActor in
                        // This closure only captures `self`
                        self.transcriptionProgress = progress
                    }
                }
                // Update the task-scoped variables
                transcript = localTranscript
                words = localWords
            } catch WhisperError.transcriptionInterrupted {
                NSLog("RecorderViewModel: Transcription was interrupted.")
                // UI reset and user notification will be handled below
                // transcript and words will remain empty or partially filled if desired
            } catch {
                NSLog("RecorderViewModel: Transcription failed with error: \(error)")
                // Handle other errors (e.g., model load, audio read)
                // transcript and words will remain empty
            }

            // WhisperEngine.shared.release() is now called internally by WhisperEngine's defer block
            // await WhisperEngine.shared.release() // This call might be redundant now
            await Task.yield()

            // Capture transcript and words as immutable constants before passing to MainActor context
            let finalTranscript = transcript
            let finalWords = words

            await MainActor.run {
                self.isProcessing = false
                self.isPreparingModel = false // Ensure this is also reset

                if finalTranscript.isEmpty && finalWords.isEmpty {
                    // Transcription likely failed or was interrupted significantly
                    // Keep the placeholder or update with minimal info
                    // Optionally, inform the user more directly here
                    NSLog("RecorderViewModel: Transcription resulted in empty content. Placeholder remains or is minimally updated.")
                    // Reset progress if it wasn't fully reset (e.g. error before loop start)
                    self.transcriptionProgress = 0.0
                    // Potentially remove the placeholder if it's truly unusable or notify user
                    // For now, we'll let the placeholder be updated with empty transcript
                }
                
                let note = Note(id: placeholderID,
                                createdAt: Date(), // Explicit Date(), ideally original placeholder's date
                                duration: duration,
                                audioURL: audioURL,
                                transcript: finalTranscript, // Use captured constant
                                words: finalWords)           // Use captured constant
                self.finishedNote = note // This might trigger UI even if transcript is empty

                // Update the note in the persistent store (replace placeholder)
                self.store?.update(note)

                // LLM post-processing is no longer automatically triggered here.
                // It should be triggered manually via manuallyRunPostProcessing(for:)
            }
        }
    }

    // MARK: – LLM post-processing

    /// Manually triggers the enhancement pipeline for a given note.
    /// This should be called based on user action (e.g., tapping a button).
    /// It delegates to the shared `enqueueEnhancement` helper.
    func manuallyRunPostProcessing(for note: Note) {
        // Ensure we have a transcript before attempting enhancement
        guard !note.transcript.isEmpty, let store = self.store else {
            NSLog("RecorderViewModel: Cannot run post-processing for note \(note.id) - transcript is empty or store is nil.")
            return
        }
        NSLog("RecorderViewModel: Manually triggering post-processing for note \(note.id)")
        // Delegate to the existing enqueue logic (assuming it handles background tasks appropriately)
        enqueueEnhancement(for: note, in: store)
    }

    // MARK: – Transcription via whisper.cpp (runs on a background actor)
    // This method is no longer directly called for transcription initiation.
    // The new WhisperEngine.transcribe(audioFileURL:progressHandler:) is used.
    // Keeping readPCM16WaveFile as it might be a useful utility, or remove if confirmed unused.

    // Helper: load WAV samples into Float array (Potentially unused for transcription flow now)
    // If WhisperEngine handles all audio reading, this can be removed or kept as a general utility.
    // For now, let's keep it commented out or marked for review.
    /*
    private static func readPCM16WaveFile(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count > 44 else { return [] }
        var out: [Float] = []
        out.reserveCapacity((data.count - 44) / 2)
        data.withUnsafeBytes { ptr in
            let bytes = ptr.bindMemory(to: UInt8.self)
            var idx = 44
            while idx + 1 < data.count {
                let value = UInt16(bytes[idx]) | (UInt16(bytes[idx + 1]) << 8)
                let intSample = Int16(bitPattern: value)
                out.append(Float(intSample) / 32768.0)
                idx += 2
            }
        }
        return out
    }
    */
}
