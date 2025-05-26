import SwiftUI
import AVFoundation
#if canImport(StoreKit)
import StoreKit
#endif

/// Full-screen sheet that records audio and runs Whisper transcription.
struct RecorderSheet: View {
    @Environment(NoteStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm = RecorderViewModel()

#if canImport(UIKit)
    @State private var showUpgrade = false
#endif

    var body: some View {
        VStack(spacing: 32) {
            Group {
                if vm.permissionDenied {
                    Text("Microphone access denied.\nEnable it in Settings.")
                        .multilineTextAlignment(.center)
                } else if vm.isRecording && vm.isPaused {
                    Text("Paused")
                        .font(.title3)
                } else if vm.isPreparingModel {
                    Text("Local AI is trascribing")
                        .multilineTextAlignment(.center)
                        .font(.title3)
                } else if vm.isProcessing {
                    Text("Transcribing…")
                        .multilineTextAlignment(.center)
                        .font(.title3)
                } else if vm.isProcessing {
                    Text("Transcribing…")
                        .font(.title3)
                } else {
                    Text("Ready")
                }
            }

            if !vm.isPreparingModel {
                Text(vm.elapsed.mmSS)
                    .font(.system(size: 48, weight: .medium, design: .rounded))
            }

            AudioLevelIndicatorView(audioLevel: vm.audioLevel)
                .padding(.vertical) // Add some space around it

            if vm.isRecording {
                HStack(spacing: 40) {
                    // Pause/Resume Button
                    Button {
                        if vm.isPaused {
                            vm.resumeRecording()
                        } else {
                            vm.pauseRecording()
                        }
                    } label: {
                        Image(systemName: vm.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 32))
                            .frame(width: 60, height: 60)
                            .foregroundStyle(.white)
                            .background(Color.gray)
                            .clipShape(Circle())
                    }
                    .disabled(vm.isProcessing || vm.isPreparingModel) // Disable if processing/preparing

                    // Stop Button
                    RecordButton(isRecording: true) { // Always show stop icon when recording
                        Task { vm.stopRecording() }
                    }
                    .disabled(vm.isProcessing || vm.isPreparingModel) // Disable if processing/preparing
                }
            } else {
                // Start Button
                RecordButton(isRecording: false) {
                    Task { vm.startRecording() }
                }
                .disabled(vm.permissionDenied || vm.isProcessing || vm.isPreparingModel)
            }

            if vm.isProcessing {
                ProgressView(value: vm.transcriptionProgress)
                    .padding(.horizontal) // Add some horizontal padding
            } else if vm.isPreparingModel {
                ProgressView()
            }
        }
        .padding()
        // Prevent the user from swiping down while a recording or processing is in progress
        .interactiveDismissDisabled(vm.isRecording || vm.isPreparingModel || vm.isProcessing) // Keep this logic, pausing is still an active recording session
        .task {
            vm.attachStore(store)
            let granted = await vm.ensurePermission()
            if granted {
                // No limits in open source version - always allow recording
                vm.startRecording()
            }
        }
#if canImport(UIKit)
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheet().environment(PurchaseManager.shared)
        }
#endif
        .onChange(of: vm.finishedNote) { _, newValue in
            if newValue != nil {
                dismiss()
            }
        }
    }

    private func canRecordMore() -> Bool {
        // No limits in open source version - always allow recording
        return true
    }
}
