import Foundation
#if canImport(UIKit)
import UIKit
#endif
// import WalkWrite // Attempting to resolve scope issues, assuming WalkWrite is the module name

#if canImport(UIKit)
private actor BackgroundTaskActor: Sendable {
    var id: UIBackgroundTaskIdentifier = .invalid

    func setID(_ newID: UIBackgroundTaskIdentifier) {
        self.id = newID
    }

    func getID() -> UIBackgroundTaskIdentifier {
        return self.id
    }

    func endAndClearTask(forNoteID noteID: UUID) async {
        if self.id != .invalid {
            let idToEnd = self.id
            self.id = .invalid // Clear before await to prevent re-entrancy issues if endBackgroundTask is slow
            NSLog("BackgroundTaskActor: Ending task \(idToEnd) for note \(noteID)")
            await UIApplication.shared.endBackgroundTask(idToEnd)
        }
    }
}
#endif

/// Lightweight tracker that remembers which notes currently have an enhancement
/// pipeline running so we do not launch duplicate jobs. Runs as an `actor` so
/// callers can safely query and mutate state from any thread.
actor PostProcessTracker {
    static let shared = PostProcessTracker()

    // At most ONE note processed at a time to keep peak RAM well below the
    // iOS 3-GB limit when Qwen + Whisper overlap briefly.
    private var current: UUID?

    /// Returns `true` when the caller successfully acquired the singleton slot.
    func start(_ id: UUID) -> Bool {
        guard current == nil else { return false }
        current = id
        return true
    }

    func finish(_ id: UUID) {
        if current == id { current = nil }
    }

    func isProcessing(_ id: UUID) -> Bool {
        current == id
    }
}

/// Kick off the three-step LLM enhancement pipeline (clean transcript → summary
/// → key ideas) for a given note. The heavy work is performed in a detached
/// task so the caller returns immediately. Partial results are persisted to the
/// supplied `NoteStore` as soon as each stage finishes so that users can see
/// them appear without waiting for the entire pipeline.
public func enqueueEnhancement(for note: Note, in store: NoteStore) { // Made public
    Task { @MainActor in
        // Reset failure flag and persist immediately so UI updates.
        var fresh = note
        fresh.enhancementFailed = nil
        store.update(fresh)
    }

    Task.detached(priority: .utility) { [weak store] in
        #if canImport(UIKit)
        let taskActor = BackgroundTaskActor() // Create instance per enqueue call

        let systemTaskID = await UIApplication.shared.beginBackgroundTask(withName: "LLMEnhancement-\(note.id)") {
            // Expiration handler
            Task {
                let idToExpire = await taskActor.getID() // Get ID before clearing
                NSLog("LLM Enhancement background task expiring for note \(note.id) (ID: \(idToExpire)). Forcing cancellation.")
                await LLMEngine.shared.forceCancelOperations()
                await taskActor.endAndClearTask(forNoteID: note.id) // Safely end and clear
            }
        }
        await taskActor.setID(systemTaskID) // Store the ID in the actor

        let initialActorTaskID = await taskActor.getID()
        NSLog("LLM Enhancement background task started: \(initialActorTaskID) for note \(note.id)")
        #endif

        // Prevent duplicate runs for the same note.
        // Re-adding await to see if it resolves type resolution issues.
        // The original warning "No 'async' operations occur within 'await' expression" was suspicious.
        guard await PostProcessTracker.shared.start(note.id) else {
            NSLog("LLM Enhancement for note \(note.id) already in progress or tracker busy. Exiting.")
            // If we return here, the defer block below will handle ending the background task if it was started.
            return
        }

        defer {
            Task { // This Task is for PostProcessTracker
                await PostProcessTracker.shared.finish(note.id)
                NSLog("LLM Enhancement PostProcessTracker finished for note \(note.id)")
            }
            #if canImport(UIKit)
            // Defer block for background task
            Task { // This Task is for ending the background task via the actor
                let idInDefer = await taskActor.getID()
                if idInDefer != .invalid { // Check if it wasn't already cleared by expiration
                     NSLog("LLM Enhancement background task ending in defer: \(idInDefer) for note \(note.id)")
                } else {
                     NSLog("LLM Enhancement background task potentially already ended or cleared before defer for note \(note.id)")
                }
                await taskActor.endAndClearTask(forNoteID: note.id) // Safely end and clear
            }
            #endif
        }

        // Run serially to minimise peak memory usage.
        do {
            NSLog("LLM Enhancement starting cleanedTranscript for note \(note.id)")
            let cleaned = try await LLMEngine.shared.cleanedTranscript(from: note.transcript)

            NSLog("LLM Enhancement completed cleanedTranscript for note \(note.id)")
            if let store {
                await MainActor.run {
                    if var n = store[note.id] {
                        n.cleanedTranscript = cleaned
                        store.update(n)
                        NSLog("LLM Enhancement updated NoteStore with cleanedTranscript for note \(note.id)")
                    }
                }
            }

            NSLog("LLM Enhancement starting summary for note \(note.id)")
            let summary = try await LLMEngine.shared.summary(for: cleaned)
            NSLog("LLM Enhancement completed summary for note \(note.id)")

            if let store {
                await MainActor.run {
                    if var n = store[note.id] {
                        n.summary = summary
                        store.update(n)
                        NSLog("LLM Enhancement updated NoteStore with summary for note \(note.id)")
                    }
                }
            }

            NSLog("LLM Enhancement starting keyIdeas for note \(note.id)")
            let ideas = try await LLMEngine.shared.keyIdeas(for: cleaned)
            NSLog("LLM Enhancement completed keyIdeas for note \(note.id)")

            if let store {
                await MainActor.run {
                    if var n = store[note.id] {
                        n.keyIdeas = ideas
                        n.enhancementFailed = false // Explicitly set to false on full success
                        store.update(n)
                        NSLog("LLM Enhancement updated NoteStore with keyIdeas and success for note \(note.id)")
                    }
                }
            }

            // Free MLX buffers / weights ASAP.
            NSLog("LLM Enhancement unloading LLMEngine for note \(note.id)")
            await LLMEngine.shared.unload()
            NSLog("LLM Enhancement LLMEngine unloaded for note \(note.id)")

        } catch {
            NSLog("LLM pipeline failed for note \(note.id): \(error)")
            // Check if it was a cancellation error specifically
            if let llmError = error as? LLMError, llmError == .generationCancelledOrInBackground {
                NSLog("LLM pipeline for note \(note.id) was cancelled or app went to background.")
                // Depending on desired behavior, you might not set enhancementFailed = true
                // if it's a user-initiated cancellation or backgrounding.
                // For now, we'll still mark it as failed so user can retry if needed.
            }

            if let store {
                await MainActor.run {
                    if var n = store[note.id] {
                        n.enhancementFailed = true
                        store.update(n)
                        NSLog("LLM Enhancement updated NoteStore with failure for note \(note.id)")
                    }
                }
            }
        }
    }
}
