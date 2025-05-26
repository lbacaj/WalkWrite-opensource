import SwiftUI
import StoreKit

/// Simple paywall sheet with one-time purchase & restore buttons.
struct UpgradeSheet: View {
    @Environment(PurchaseManager.self) private var purchase
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.yellow)

                Text("Unlock Walk & Write Full – Lifetime")
                    .font(.title).bold()

                Text("• Unlimited notes & length\n• Export transcript & audio\n• Future on-device AI upgrades")
                    .multilineTextAlignment(.center)

                if let p = purchase.product {
                    Button(action: { Task { try? await purchase.buy(); dismiss() } }) {
                        Text("Full Unlock – \(p.displayPrice)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                } else {
                    ProgressView().task { await purchase.loadProduct() }
                }

                Button("Restore Purchase") {
                    Task { await purchase.restore(); dismiss() }
                }
                .padding(.top, 8)

                Spacer()
            }
            .padding()
            .navigationTitle("Unlock WalkWrite Full")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", action: { dismiss() }) } }
        }
    }
}
