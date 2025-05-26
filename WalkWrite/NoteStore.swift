import Foundation
import Observation

/// Simple JSON-backed store that keeps all `Note` metadata in memory and
/// persists changes to disk. We avoid Core Data for V1 to keep things light.
@Observable
@MainActor
public final class NoteStore {

    /// Published list of notes, newest first.
    private(set) var notes: [Note] = [] {
        didSet { persist() }
    }

    /// Replace an existing note with an updated version (matched by id).
    func update(_ note: Note) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        }
    }

    /// Delete a specific note instance.
    func delete(_ note: Note) {
        if let idx = notes.firstIndex(of: note) {
            delete(at: IndexSet(integer: idx))
        }
    }

    init() {
        load()
    }

    // MARK: – CRUD

    func add(_ note: Note) {
        notes.insert(note, at: 0)
    }

    func delete(at offsets: IndexSet) {
        let doomed = offsets.map { notes[$0] }
        doomed.forEach { try? FileManager.default.removeItem(at: $0.audioURL) }
        notes.remove(atOffsets: offsets)
    }

    subscript(id: UUID) -> Note? {
        notes.first { $0.id == id }
    }

    // MARK: – File IO

    private func load() {
        guard let data = try? Data(contentsOf: Note.indexFile),
              let list = try? JSONDecoder().decode([Note].self, from: data) else {
            return
        }
        notes = list.sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: Note.indexFile, options: .atomicWrite)
        } catch {
            // In production we’d log locally.
            print("⚠️ Failed to persist notes: \(error)")
        }
    }
}
