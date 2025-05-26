import SwiftUI

/// Big circular mic/stop button that toggles recording state.
struct RecordButton: View {
    var isRecording: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .foregroundStyle(isRecording ? .red : .accentColor)
                    .frame(width: 88, height: 88)

                if isRecording {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                }
            }
        }
        .shadow(radius: 4)
    }
}

#Preview("Idle") {
    RecordButton(isRecording: false) {}
}

#Preview("Recording") {
    RecordButton(isRecording: true) {}
}
