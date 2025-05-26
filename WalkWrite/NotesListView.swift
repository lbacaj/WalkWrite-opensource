import SwiftUI
import StoreKit

struct NotesListView: View {
    @Environment(NoteStore.self) private var store
    @State private var showRecorder = false
    @State private var showInfo = false

    // Search
    @State private var searchText: String = ""

#if canImport(UIKit)
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showUpgrade = false
#endif

    // Computed list after search filter
    private var filteredNotes: [Note] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return store.notes
        }
        return store.notes.filter { $0.transcript.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            let notes = filteredNotes
            Group {
                if store.notes.isEmpty {
                    ContentUnavailableView(label: {
                        Label("No Notes Yet", systemImage: "mic")
                    }, description: {
                        Text("Tap Record to capture your first voice note.")
                    })
                } else {
                    List {
                        ForEach(notes) { note in
                            NavigationLink(value: note.id) {
                                NoteRow(note: note)
                            }
                            // Swipe *right* (edge: .leading) to share. Keep default Delete on trailing side.
#if canImport(UIKit)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    share(note: note)
                                } label: {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .tint(.blue)
                            }
#endif
                        }
                        .onDelete(perform: store.delete)
                    }
                }
            }
            .navigationTitle("WalkWrite: Notes")
            .safeAreaInset(edge: .bottom) {
                RecordButton(isRecording: false) {
                    // Check if WhisperStateManager indicates readiness
                    if WhisperStateManager.shared.canAcceptNewJob() {
                        showRecorder = true
                    } else {
                        // Optional: Add user feedback here (e.g., alert)
                        Foundation.NSLog("NotesListView: Record button tapped, but WhisperStateManager indicates busy (transcribing or releasing).")
                    }
                }
                .padding(.bottom, 40)
            }
            .navigationDestination(for: UUID.self) { id in
                if let note = store[id] {
                    NoteDetailView(note: note)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .searchable(text: $searchText, placement: .automatic, prompt: "Search transcripts")
            .sheet(isPresented: $showInfo) {
                InfoSheet()
            }
            .sheet(isPresented: $showRecorder) {
                RecorderSheet()
            }
#if canImport(UIKit)
            .sheet(isPresented: $showShareSheet, onDismiss: cleanupTempFile) {
                ShareSheet(shareItems)
            }
            .sheet(isPresented: $showUpgrade) {
                UpgradeSheet().environment(PurchaseManager.shared)
            }
#endif
        }
    }

#if canImport(UIKit)
    // MARK: – Share helpers

    private func share(note: Note) {
        guard PurchaseManager.shared.allowExport() else {
            #if canImport(UIKit)
            showUpgrade = true
            #endif
            return
        }
        do {
            let (body, url) = try TranscriptSharing.makeItems(for: note)
            shareItems = [body, url]
            showShareSheet = true
        } catch {
            print("Failed to prepare share items: \(error)")
        }
    }

    private func cleanupTempFile() {
        if let url = shareItems.first(where: { $0 is URL }) as? URL {
            try? FileManager.default.removeItem(at: url)
        }
        shareItems = []
    }
#endif
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading) {
            Text(note.transcript.isEmpty ? "(No transcript)" : String(note.transcript.prefix(40)))
                .font(.headline)
                .lineLimit(1)

            HStack {
                Text(note.createdAt.formatted(.dateTime.year().month().day().hour().minute()))
                Spacer()
                Text(note.duration.mmSS)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let store = NoteStore()
    return NotesListView()
        .environment(store)
}
