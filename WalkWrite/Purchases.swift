import Foundation
import StoreKit

/// Simple StoreKit-2 wrapper that loads the non-consumable “Pro Unlock” product,
/// allows the user to buy / restore it, and publishes the `isUnlocked` flag.
@MainActor
@Observable
public final class PurchaseManager: NSObject, SKPaymentTransactionObserver { // Made public

    public static let shared = PurchaseManager() // Made public

    // MARK: – Configuration
    private let productID = "com.walkwrite.fullunlock" // matches App Store Connect Product ID

    // MARK: – Published state
    public private(set) var isUnlocked: Bool { // Made public(set)
        didSet { UserDefaults.standard.set(isUnlocked, forKey: Self.udKey) }
    }

    // MARK: – Export gating
    /// Returns true if user can export/share right now. 
    /// In open source version, export is always allowed.
    func allowExport() -> Bool {
        // No limits in open source version - always allow export
        return true
    }

    private(set) var exportsUsed: Int {
        didSet { UserDefaults.standard.set(exportsUsed, forKey: Self.udExportsKey) }
    }

    private(set) var product: Product?

    // MARK: – Init
    private static let udKey = "walkwrite_isUnlocked"
    private static let udExportsKey = "walkwrite_exportsUsed"

    private override init() {
        let defaults = UserDefaults.standard
        self.isUnlocked = defaults.bool(forKey: Self.udKey)
        self.exportsUsed = defaults.integer(forKey: Self.udExportsKey)
        super.init()
        SKPaymentQueue.default().add(self) // Add as observer
        Task { await self.refreshPurchased() }
    }

    // MARK: – API
    /// Requests StoreKit for the product info.
    public func loadProduct() async { // Made public
        guard product == nil else { return }
        do {
            let products = try await Product.products(for: [productID])
            self.product = products.first
        } catch {
            print("⚠️ StoreKit load error: \(error)")
        }
    }

    /// Starts the purchase flow.
    public func buy() async throws { // Made public
        guard let product else { return }
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            _ = try checkVerified(verification)
            self.isUnlocked = true
        default:
            break
        }
    }

    /// Restore purchases button handler.
    public func restore() async { // Made public
        do {
            try await AppStore.sync()
            await refreshPurchased()
        } catch {
            print("Restore failed: \(error)")
        }
    }

    // MARK: – Helpers

    /// Handles transaction updates from the `Transaction.updates` listener.
    @MainActor // Ensure UI updates happen on the main thread
    public func handleTransactionUpdate(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else {
            print("Transaction update failed verification.")
            // Decide if unverified transactions should be finished.
            // Generally, it's safer not to finish them automatically.
            return
        }

        // Check if it's the correct product and if it's a new purchase/restore
        if transaction.productID == self.productID && (transaction.revocationDate == nil) {
            print("Transaction update received for \(transaction.productID), setting unlocked.")
            // Ensure isUnlocked update happens on MainActor
             self.isUnlocked = true
            await transaction.finish() // IMPORTANT: Finish the transaction
        } else {
            // Handle other cases if necessary (e.g., revoked transaction, other products)
            print("Received irrelevant transaction update or revocation: \(transaction.productID)")
            // Decide if other transactions should be finished. For a single non-consumable,
            // finishing might not be strictly necessary unless they clutter the queue.
            // await transaction.finish()
        }
    }

    private func refreshPurchased() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == productID {
                self.isUnlocked = true
                return
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }
}

// MARK: – Free-tier limits helper

struct FreeTierLimit {
    // Note: These limits are not enforced in the open source version
    // They're kept for reference but all features are unlimited
    static let maxNotes = 10000  // Effectively unlimited
    static let maxExports = 10000 // Effectively unlimited
}

// MARK: - SKPaymentTransactionObserver
extension PurchaseManager {
    public nonisolated func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) { // Made public and nonisolated
        Task { @MainActor in // Dispatch internal logic to main actor
            for transaction in transactions {
                switch transaction.transactionState {
                case .purchased, .restored:
                    if transaction.payment.productIdentifier == self.productID {
                        self.isUnlocked = true
                        print("Transaction successful: \(transaction.payment.productIdentifier)")
                    }
                    SKPaymentQueue.default().finishTransaction(transaction)
                case .failed:
                    if let error = transaction.error {
                        print("Transaction failed: \(error.localizedDescription)")
                    }
                    SKPaymentQueue.default().finishTransaction(transaction)
                case .deferred:
                    print("Transaction deferred: \(transaction.payment.productIdentifier)")
                case .purchasing:
                    print("Transaction purchasing: \(transaction.payment.productIdentifier)")
                @unknown default:
                    print("Unknown transaction state for: \(transaction.payment.productIdentifier)")
                    SKPaymentQueue.default().finishTransaction(transaction)
                }
            }
            // After processing transactions, refresh entitlements
            await refreshPurchased()
        }
    }

    // Optional: Handle removed transactions (e.g. for subscriptions, less critical for non-consumables)
    // func paymentQueue(_ queue: SKPaymentQueue, removedTransactions transactions: [SKPaymentTransaction]) { }

    // Optional: Handle restore completed transactions (though our restore() method uses AppStore.sync())
    // func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) { }

    // Optional: Handle restore failed
    // func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) { }
}
