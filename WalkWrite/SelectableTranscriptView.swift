import SwiftUI
import UIKit

struct SelectableTranscriptView: UIViewRepresentable {
    var attributedString: AttributedString

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear // Match app's background
        textView.textContainerInset = .zero // Remove default padding if SwiftUI handles it
        textView.isScrollEnabled = false // Let SwiftUI's ScrollView handle scrolling
        
        // Apply initial text, converting SwiftUI AttributedString to NSAttributedString
        textView.attributedText = NSAttributedString(attributedString)
        
        // Ensure it can be sized correctly by SwiftUI
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal) // Keep low for width, allow wrapping
        textView.setContentCompressionResistancePriority(.required, for: .vertical)   // Resist vertical compression
        textView.setContentHuggingPriority(.required, for: .vertical)                // Prefer intrinsic height
        
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let nsAttributedString = NSAttributedString(attributedString)
        // Only update if the text has actually changed to avoid unnecessary work
        // Also check if the view's frame width might have changed, which could affect text layout
        if uiView.attributedText != nsAttributedString || uiView.bounds.width != context.coordinator.lastWidth {
            uiView.attributedText = nsAttributedString
            context.coordinator.lastWidth = uiView.bounds.width
            // After text change, it's important to invalidate intrinsic content size
            // so that SwiftUI re-calculates the layout for the UIViewRepresentable.
            uiView.invalidateIntrinsicContentSize()
        }
    }

    // Coordinator to store last known width to help with updates if width changes affect height
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var lastWidth: CGFloat = 0
    }
}

// Optional: Preview for SelectableTranscriptView itself, if needed for isolated testing
#if DEBUG
struct SelectableTranscriptView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a sample AttributedString
        var sampleText = AttributedString("Hello, ")
        var boldText = AttributedString("world!")
        boldText.font = .headline
        boldText.foregroundColor = .blue
        sampleText.append(boldText)
        sampleText.append(AttributedString(" This is a test of selectable attributed text."))
        
        return ScrollView { // Wrap in ScrollView for preview if content is long
            SelectableTranscriptView(attributedString: sampleText)
                .padding()
        }
    }
}
#endif
