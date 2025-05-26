import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Helper that builds the shareable artefacts (plain body text + `.txt` file)
/// for a given `Note`'s transcript.
enum TranscriptSharing {

    /// Returns tuple `(bodyText, fileURL)` where:
    ///  - `bodyText` is the full transcript – ready for Mail body or Messages bubble.
    ///  - `fileURL`  is a temporary text file that contains the transcript with per-word time-stamps.
    /// The caller is responsible for deleting the file afterwards if desired.
    static func makeItems(for note: Note) throws -> (String, URL) {
        // 1. Body text: just return the raw transcript string.
        let body = note.transcript

        // 2. Build timestamped lines (one per word) e.g. [00:03.42] Hello
        let lines: String = note.words.map { word in
            let minutes = Int(word.start) / 60
            let seconds = Int(word.start) % 60
            let fraction = Int((word.start - floor(word.start)) * 100) // centiseconds
            return String(format: "[%02d:%02d.%02d] %@", minutes, seconds, fraction, word.word)
        }.joined(separator: "\n")

        // If there are no word-level timestamps fall back to single block
        let txtContent = lines.isEmpty ? body : lines

        // 3. Write to a temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("VoiceMemoTranscript.txt")
        try txtContent.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)

        return (body, fileURL)
    }
}

#if canImport(UIKit)
// MARK: - ShareSheet wrapper

import SwiftUI

/// SwiftUI wrapper around `UIActivityViewController` so we can present the system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?

    init(_ items: [Any], applicationActivities: [UIActivity]? = nil) {
        self.activityItems = items
        self.applicationActivities = applicationActivities
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems,
                                 applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Mail composer wrapper

import MessageUI

/// SwiftUI wrapper around `MFMailComposeViewController`.
struct MailComposer: UIViewControllerRepresentable {
    typealias Callback = (MFMailComposeResult, Error?) -> Void

    let subject: String
    let body: String
    let attachments: [URL]?
    var completion: Callback?

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)

        if let atts = attachments {
            for url in atts {
                if let data = try? Data(contentsOf: url) {
                    let mime = url.pathExtension.lowercased() == "wav" ? "audio/wav" : "text/plain"
                    vc.addAttachmentData(data, mimeType: mime, fileName: url.lastPathComponent)
                }
            }
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        var completion: Callback?

        init(completion: Callback?) { self.completion = completion }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            completion?(result, error)
            controller.dismiss(animated: true)
        }
    }
}
#endif
