import Foundation
import Combine

@MainActor
public final class WhisperStateManager: ObservableObject { // Made public
    public static let shared = WhisperStateManager() // Made public

    @Published public private(set) var isTranscribing: Bool = false // Getter is public
    @Published public private(set) var isReleasingContext: Bool = false // Getter is public

    private init() {} // Private init for singleton

    // --- Methods to be called by WhisperEngine ---

    public func setIsTranscribing(_ status: Bool) async { // Made public
        // Since this whole class is @MainActor, direct assignment is fine.
        // The async nature is for the caller on a different actor.
        isTranscribing = status
        Foundation.NSLog("WhisperStateManager: isTranscribing set to \(status).")
    }

    public func setIsReleasingContext(_ status: Bool) async { // Made public
        // Since this whole class is @MainActor, direct assignment is fine.
        isReleasingContext = status
        Foundation.NSLog("WhisperStateManager: isReleasingContext set to \(status).")
    }

    // --- Method for UI to check ---
    
    public func canAcceptNewJob() -> Bool { // Made public
        let canAccept = !isTranscribing && !isReleasingContext
        Foundation.NSLog("WhisperStateManager: Checking if can accept new job. Transcribing: \(isTranscribing), Releasing: \(isReleasingContext). Result: \(canAccept)")
        return canAccept
    }
}
