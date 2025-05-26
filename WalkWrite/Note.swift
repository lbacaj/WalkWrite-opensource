import Foundation

// WordStamp is now defined in WhisperEngine.swift

    /// Domain model representing one voice note.
public struct Note: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var duration: TimeInterval
    public var audioURL: URL        // path on disk
    public var transcript: String
    public var words: [WordStamp]

    // MARK: – LLM post-processing results (optional)
    /// Transcript after grammar/filler-word cleanup produced by Gemma.
    public var cleanedTranscript: String?

    /// One-paragraph gist of the note.
    public var summary: String?

    /// Up to ten key ideas extracted and lightly elaborated by the LLM.
    public var keyIdeas: [String]?

    /// Flag persisted when the last attempt at generating the cleaned transcript
    /// / summary / key-ideas pipeline failed. `nil` means no attempt yet or the
    /// last run succeeded, `true` indicates the most recent run threw and
    /// aborted early. UI can surface a "Try Again" button based on this.
    public var enhancementFailed: Bool?

    public init(id: UUID = .init(),
                createdAt: Date = .now,
                duration: TimeInterval = 0,
                audioURL: URL,
                transcript: String = "",
                words: [WordStamp] = [],
                cleanedTranscript: String? = nil,
                summary: String? = nil,
                keyIdeas: [String]? = nil,
                enhancementFailed: Bool? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.audioURL = audioURL
        self.transcript = transcript
        self.words = words

        self.cleanedTranscript = cleanedTranscript
        self.summary = summary
        self.keyIdeas = keyIdeas
        self.enhancementFailed = enhancementFailed
    }

    // MARK: – Persistence helper

    static var indexFile: URL {
        AppFolders.notes.appendingPathComponent("notes.json")
    }
}
