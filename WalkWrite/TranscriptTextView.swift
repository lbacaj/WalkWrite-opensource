import SwiftUI

#if canImport(UIKit)
/// A UIViewRepresentable wrapper around UITextView that shows an `AttributedString`
/// and allows the user to select/copy arbitrary ranges. It is non-editable & non-scrolling
/// (the parent SwiftUI ScrollView provides scrolling).
struct TranscriptTextView: UIViewRepresentable {
    var attributed: AttributedString

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = NSAttributedString(attributed)
    }
}
#endif