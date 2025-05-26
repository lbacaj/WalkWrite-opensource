//
//  WalkWriteApp.swift
//  WalkWrite
//

import SwiftUI
import StoreKit // Import StoreKit for Transaction
import Foundation // Add Foundation just in case

@main
struct WalkWriteApp: App {

    @State private var store = NoteStore()

    init() {
        // Ensure the application document directory exists early so subsequent
        // file writes never throw.
        _ = AppFolders.notes

        // Perform initial purchase manager setup (optional, but good practice)
        // This ensures the shared instance is created early.
        _ = PurchaseManager.shared
    }

    var body: some Scene {
        WindowGroup {
            NotesListView()
                .environment(store)
                // Intentionally **no** automatic enhancement resume. Users can
                // trigger generation from the Note detail screen to avoid
                // background jobs that may surprise them or exceed memory.
                .task { // Add task to listen for transaction updates
                    // Start listening for transaction updates
                    for await update in Transaction.updates {
                        // Handle the transaction update using the PurchaseManager
                        await PurchaseManager.shared.handleTransactionUpdate(update)
                    }
                }
        }
    }
}
