import SwiftUI
import StoreKit
import Foundation // Added for PurchaseManager dependencies
// Removed UIKit import; SwiftUI might handle UIImage resolution

/// Simple sheet that shows branding, a short description and links to the
/// Terms of Service and Privacy Policy. This fulfils App Store requirements
/// for legal documents.
struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let accent = Color.accentColor

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // App icon. Using fallback symbol directly.
                Image(systemName: "mic")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .padding(.bottom) // Add some padding like the original might have had

                VStack(spacing: 4) {
                    Text("WalkWrite: Notes")
                        .font(.title).bold()

                    Text("Transcribed Voice Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Purchase / Restore section
                if !PurchaseManager.shared.isUnlocked {
                    VStack(spacing: 12) {
                        Button("Full Lifetime Unlock – $1.99") {
                            Task {
                                do {
                                    await PurchaseManager.shared.loadProduct() // Ensure product is loaded
                                    try await PurchaseManager.shared.buy()
                                } catch {
                                    print("Purchase failed: \(error)")
                                    // Optionally show an alert to the user here
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        // Restore purchases button required by App Store Review Guideline 3.1.1
                        Button("Restore Purchase") {
                            Task { await PurchaseManager.shared.restore() }
                        }
                        .font(.footnote)
                    }
                } else {
                    VStack(spacing: 12) {
                        Text("Full Lifetime Unlocked – Thank you!")
                            .font(.footnote)
                            .foregroundStyle(.green)

                        // Even after an unlock, keep the Restore button visible so that users
                        // who reinstall the app (or reviewers using test accounts) can easily
                        // restore their purchase again from a single, predictable place.
                        Button("Restore Purchase") {
                            Task { await PurchaseManager.shared.restore() }
                        }
                        .font(.footnote)
                    }
                }

                Text("Voice notes are transcribed by state-of-the-art **local** models. Your recordings never have to leave your device, keeping them private & secure.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(spacing: 16) {
                    Link(destination: URL(string: "https://motivationstack.com/Terms")!) {
                        Label("Terms of Service", systemImage: "doc.text")
                    }
                    Link(destination: URL(string: "https://motivationstack.com/privacy")!) {
                        Label("Privacy Policy", systemImage: "lock.shield")
                    }
                }

                Spacer()

                HStack(spacing: 2) {
                    Text("Made with ❤️ by")
                    Link("Louie Bacaj", destination: URL(string: "https://x.com/lbacaj")!)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom)
            }
            .padding()
            .task { await PurchaseManager.shared.loadProduct() }
            .navigationTitle("About")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: { dismiss() }) } }
        }
    }
}

// Removed private struct AppIconView to avoid UIImage dependency issues.

#Preview {
    InfoSheet()
}
