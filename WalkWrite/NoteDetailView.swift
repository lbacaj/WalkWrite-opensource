import SwiftUI
import AVFoundation
import Combine
#if canImport(MessageUI)
import MessageUI
#endif

#if canImport(StoreKit)
import StoreKit
#endif

/// Detail screen that shows full transcript and allows playback.
struct NoteDetailView: View {
    @Environment(NoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var note: Note   // copy so edits don’t mutate store yet
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var playbackTime: TimeInterval = 0
    @State private var timerCancellable: AnyCancellable?

    // Share & email presentation state
#if canImport(UIKit)
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    @State private var showMailComposer = false // Will be replaced by mailInfo != nil
    // @State private var mailData: (subject: String, body: String, attachments: [URL])? // Replaced by mailInfo
    @State private var mailInfo: MailInfo? // New state variable for item-based sheet

    @State private var showDeleteConfirm = false

    @State private var showUpgradeSheet = false
#endif

    @State private var selectedTab = 0
    @State private var enhancementRequested = false
    @State private var isRetryingTranscription = false // For retry UI
    @State private var showWhisperBusyAlert = false // For retry UI

    // MARK: – Helper flags
    private var noEnhancementsYet: Bool {
        note.cleanedTranscript == nil && note.summary == nil && note.keyIdeas == nil && note.enhancementFailed == nil
    }

    var body: some View {
        VStack {
            TabView(selection: $selectedTab) {
                transcriptTab()
                    .tabItem { Text("Transcript") }
                    .tag(0)
                cleanTab()
                    .tabItem { Text("Clean Up") }
                    .tag(1)
                summaryTab()
                    .tabItem { Text("Summary") }
                    .tag(2)
                ideasTab()
                    .tabItem { Text("Core Ideas") }
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .onChange(of: selectedTab) { _, _ in }

            // MARK: – Playback controls
            HStack(spacing: 32) {
                Button(action: togglePlay) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }

#if canImport(UIKit)
                Button(action: prepareMail) {
                    Image(systemName: "paperplane")
                        .font(.system(size: 36))
                }

                Button(action: prepareMailFull) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 36))
                }
#endif

                Spacer()
                Text(note.duration.mmSS)
            }
            .padding()
        }
        .alert("Transcription Busy", isPresented: $showWhisperBusyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The transcription engine is currently busy with another task. Please try again in a moment.")
        }
        // Keep our local copy in sync with the latest version in the store so
        // that LLM results appear when they arrive.
        .onChange(of: store.notes) { _, _ in
            if let updated = store[note.id] {
                self.note = updated
                // Hide loader when work finishes or fails.
                if updated.enhancementFailed != nil || (updated.cleanedTranscript != nil && updated.summary != nil && updated.keyIdeas != nil) {
                    enhancementRequested = false
                }
            }
        }
        .navigationTitle("Note")
#if canImport(UIKit)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: prepareShare) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
#endif
        .onDisappear {
            player?.stop()
            timerCancellable?.cancel()
        }
#if canImport(UIKit)
        .sheet(isPresented: $showUpgradeSheet) {
            UpgradeSheet().environment(PurchaseManager.shared)
        }
#endif
#if canImport(UIKit)
        .alert("Delete this note?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteNote() }
            Button("Cancel", role: .cancel) {}
        }
#endif
#if canImport(UIKit)
        .sheet(isPresented: $showShareSheet, onDismiss: cleanupTempFile) {
            ShareSheet(shareItems)
        }
        .sheet(item: $mailInfo, onDismiss: cleanupTempFile) { info in
            MailComposer(subject: info.subject, body: info.body, attachments: info.attachments, completion: { _, _ in })
        }
#endif
    }

    // Identifiable struct for mail data
    struct MailInfo: Identifiable {
        let id = UUID()
        let subject: String
        let body: String
        let attachments: [URL]
    }


    // Build an attributed string that highlights the word whose timestamp
    // range currently contains `playbackTime`.
    private func highlightedTranscript() -> AttributedString {
        guard !note.words.isEmpty else { return AttributedString(note.transcript) }

        var attr = AttributedString("")
        let current = playbackTime

        for (index, w) in note.words.enumerated() {
            var piece = AttributedString(w.word)
            if current >= w.start && current <= w.end {
                piece.foregroundColor = Color.accentColor
                piece.font = Font.body.bold()
            }
            attr += piece

            // Intelligent space insertion
            if index < note.words.count - 1 {
                let nextWordString = note.words[index + 1].word

                // Check if the NEXT word is a punctuation mark that should attach to the current word
                let punctuationThatAttaches: Set<String> = [".", ",", "?", "!", ";", ":"]

                // Conditions for NOT adding a space:
                // 1. Next word is an attaching punctuation mark.
                // 2. Next word starts with an apostrophe.
                // 3. Next word is "n't" (case-insensitive).
                if punctuationThatAttaches.contains(nextWordString) || 
                   nextWordString.first == "'" || 
                   nextWordString.lowercased() == "n't" {
                    // Do not add a space
                } else {
                    attr += AttributedString(" ")
                }
            }
        }
        return attr
    }

    private func togglePlay() {
        guard FileManager.default.fileExists(atPath: note.audioURL.path) else { return }

        if player == nil {
            player = try? AVAudioPlayer(contentsOf: note.audioURL)
            player?.prepareToPlay()
        }

        guard let player else { return }

        if player.isPlaying {
            player.pause()
            isPlaying = false
            timerCancellable?.cancel()
        } else {
            player.play()
            isPlaying = true
            startProgressTimer()
        }
    }

    private func startProgressTimer() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if let p = player {
                    playbackTime = p.currentTime
                }
            }
    }

#if canImport(UIKit)
    // MARK: – Share & Email helpers

    private func prepareShare() {
        guard PurchaseManager.shared.allowExport() else {
            showUpgradeSheet = true
            return
        }
        let currentNote = self.note // Capture current note state

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (body, url) = try TranscriptSharing.makeItems(for: currentNote)
                DispatchQueue.main.async {
                    self.shareItems = [body, url]
                    DispatchQueue.main.async { // Nested dispatch
                        self.showShareSheet = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("Failed to build share items: \(error)")
                    // Optionally show an error alert to the user
                }
            }
        }
    }

    private func prepareMail() {
        guard PurchaseManager.shared.allowExport() else {
            showUpgradeSheet = true
            return
        }
        guard MFMailComposeViewController.canSendMail() else {
            // If mail is not available, fallback to share sheet.
            // This fallback itself should be asynchronous if prepareShare is.
            // For simplicity here, ensure prepareShare is also async or handle this differently.
            // Given prepareShare is now async, we should call it appropriately.
            self.prepareShare() // This will now dispatch its own async work.
            return
        }

        let currentNote = self.note // Capture current note state for the task.

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (body, url) = try TranscriptSharing.makeItems(for: currentNote) // Use the captured copy.
                DispatchQueue.main.async {
                    self.mailInfo = MailInfo(subject: "Voice memo transcript", body: body, attachments: [url])
                    // No need to set showMailComposer explicitly; sheet presentation is tied to mailInfo != nil
                }
            } catch {
                DispatchQueue.main.async {
                    print("Failed to prepare mail composer: \(error)")
                    // Optionally, you could show an error alert to the user here.
                }
            }
        }
    }

    private func prepareMailFull() {
        guard PurchaseManager.shared.allowExport() else {
            showUpgradeSheet = true
            return
        }
        guard MFMailComposeViewController.canSendMail() else {
            // Fallback to share sheet, which is now async.
            self.prepareShare()
            return
        }

        let currentNote = self.note // Capture current note state.

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let (body, txtURL) = try TranscriptSharing.makeItems(for: currentNote) // Use the captured copy.
                var finalAttachments: [URL] = [txtURL]
                finalAttachments.append(currentNote.audioURL) // Access captured note's audioURL.

                DispatchQueue.main.async {
                    self.mailInfo = MailInfo(subject: "Voice memo (audio + transcript)", body: body, attachments: finalAttachments)
                    // No need to set showMailComposer explicitly
                }
            } catch {
                DispatchQueue.main.async {
                    print("Failed to prepare full mail: \(error)")
                    // Optionally, show an error alert to the user.
                }
            }
        }
    }

    private func cleanupTempFile() {
        // Check mailInfo's attachments if it was used
        if let info = mailInfo {
            for url in info.attachments where url != note.audioURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        // Check shareItems if it was used
        if let url = shareItems.first(where: { $0 is URL }) as? URL, url != note.audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        mailInfo = nil // Reset the identifiable item
        shareItems = []
    }
#endif

    // MARK: – Delete
#if canImport(UIKit)
    private func deleteNote() {
        store.delete(note)
        dismiss()
    }
#endif

    // MARK: – Regenerate LLM results

    private func regenerateEnhancements() {
        guard var n = store[note.id] else { return }
        n.cleanedTranscript = nil
        n.summary = nil
        n.keyIdeas = nil
        n.enhancementFailed = nil
        store.update(n)
        enhancementRequested = true
        enqueueEnhancement(for: n, in: store)
    }

    private func startEnhancements() {
        guard let n = store[note.id] else { return }
        enhancementRequested = true
        enqueueEnhancement(for: n, in: store)
    }

    // MARK: – Retry Transcription Logic

    private func retryTranscription() {
        guard WhisperStateManager.shared.canAcceptNewJob() else {
            showWhisperBusyAlert = true
            Foundation.NSLog("NoteDetailView: Retry transcription tapped, but WhisperStateManager indicates busy.")
            return
        }

        isRetryingTranscription = true
        // It's crucial to use the note from the store for the ID,
        // but the audioURL from the local @State var note (which should be the same).
        // This ensures we are operating on the correct, persisted Note entity.
        guard let storeNoteID = store[note.id]?.id else {
            Foundation.NSLog("NoteDetailView: Could not find note in store for retry. ID: \(note.id)")
            isRetryingTranscription = false
            return
        }

        Task.detached(priority: .userInitiated) {
            do {
                Foundation.NSLog("NoteDetailView: Starting Whisper transcription retry for note ID \(storeNoteID)")
                // Use note.audioURL from the @State var, which is a copy but should have the correct URL
                let (newTranscript, newWords) = try await WhisperEngine.shared.transcribe(audioFileURL: note.audioURL) { progress in
                    // This closure must be synchronous.
                    // If UI updates were needed here, they'd have to be dispatched to MainActor
                    // without making this closure async. For logging, it's fine.
                    Foundation.NSLog("NoteDetailView: Retry progress for \(storeNoteID): \(progress)")
                }

                await MainActor.run {
                    if var n = store[storeNoteID] { // Fetch the latest version from store again
                        n.transcript = newTranscript
                        n.words = newWords
                        // n.transcriptionFailed = false // If you add such a flag to Note model
                        store.update(n)
                        self.note = n // Update local copy to refresh UI
                        Foundation.NSLog("NoteDetailView: Retry transcription successful for note ID \(storeNoteID).")
                    } else {
                        Foundation.NSLog("NoteDetailView: Note \(storeNoteID) not found in store after retry success.")
                    }
                    isRetryingTranscription = false
                }
            } catch {
                Foundation.NSLog("NoteDetailView: Retry transcription failed for note ID \(storeNoteID) with error: \(error)")
                await MainActor.run {
                    // Optionally update the note in store to indicate failure again
                    // if var n = store[storeNoteID] {
                    // n.transcriptionFailed = true
                    // store.update(n)
                    // self.note = n
                    // }
                    isRetryingTranscription = false
                    // Optionally show an error alert to the user
                }
            }
        }
    }

    // MARK: – Tab builders

    @ViewBuilder
    private func transcriptTab() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Transcript")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(highlightedTranscript())
                    .textSelection(.enabled)
                    .id(note.id)
                    .foregroundColor(.primary)

                // Retry Transcription Button
                if note.transcript.isEmpty && !isRetryingTranscription {
                    Button(action: retryTranscription) { // Action to be added later
                        Label("Retry Transcription", systemImage: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .padding(.top)
                } else if isRetryingTranscription {
                    ProgressView("Retrying transcription...")
                        .frame(maxWidth: .infinity)
                        .padding(.top)
                }

                // LLM Enhancement Button (only if transcript exists)
                if !note.transcript.isEmpty && !enhancementRequested && noEnhancementsYet {
                    Button(action: { startEnhancements() }) {
                        Label("Generate summary & key points", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, note.transcript.isEmpty ? 0 : 8) // Adjust spacing
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    @ViewBuilder
    private func cleanTab() -> some View {
        ScrollView {
            Text("Clean")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            if let cleaned = note.cleanedTranscript {
                Text(cleaned)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else if note.enhancementFailed == true {
                failedState() // Includes "Try Again"
            } else if enhancementRequested {
                ProgressView("Local models are securely generating… 1 / 3")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Text("No cleaned transcript yet.")
                        .foregroundStyle(.secondary)
                    Button(action: { startEnhancements() }) {
                        Label("Generate Cleaned Transcript", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func summaryTab() -> some View {
        ScrollView {
            Text("Summary")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            if let summary = note.summary {
                Text(summary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else if note.enhancementFailed == true {
                failedState() // Includes "Try Again"
            } else if enhancementRequested {
                let done = note.cleanedTranscript == nil ? 0 : 1
                ProgressView("Local models are securely generating… \(done + 1) / 3")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Text("No summary yet.")
                        .foregroundStyle(.secondary)
                    Button(action: { startEnhancements() }) {
                        Label("Generate Summary", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func ideasTab() -> some View {
        ScrollView {
            Text("Core Ideas")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            if let ideas = note.keyIdeas {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(ideas, id: \.self) { idea in
                        Text("• \(idea)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .textSelection(.enabled)
                .padding()
            } else if note.enhancementFailed == true {
                failedState() // Includes "Try Again"
            } else if enhancementRequested {
                let done = (note.cleanedTranscript != nil ? 1 : 0) + (note.summary != nil ? 1 : 0)
                ProgressView("Local models are securely generating… \(done + 1) / 3")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Text("No key ideas yet.")
                        .foregroundStyle(.secondary)
                    Button(action: { startEnhancements() }) {
                        Label("Generate Key Ideas", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // Common failed UI
    @ViewBuilder
    private func failedState() -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text("Generation stopped.")
            Button("Try Again") { regenerateEnhancements() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
    }
}

#Preview {
    let dummyURL = URL(fileURLWithPath: "/dev/null")
    let note = Note(id: UUID(), createdAt: Date(), duration: 12, audioURL: dummyURL, transcript: "Hello world", words: [])
    NavigationStack { NoteDetailView(note: note) }
}
