//
//  CoreDataStack.swift
//  ScanConvertPDF
//
//  Created by Developer on 19.01.2026.
//

import Foundation
import CoreData

final class CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    var context: NSManagedObjectContext { container.viewContext }

    private init() {
        container = NSPersistentContainer(name: "CDModel")
        Self.loadStore(into: container)

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    private static func loadStore(into container: NSPersistentContainer, isRetry: Bool = false) {
        container.loadPersistentStores { storeDescription, error in
            guard let error else {
                print("CoreData store loaded:")
                print("type:", storeDescription.type)
                print("url:", storeDescription.url?.absoluteString ?? "nil")
                return
            }

            print("Core Data load error:", error)

            guard !isRetry, let storeURL = storeDescription.url else {
                // Already retried once (or no store URL to recover from).
                // Don't crash the app on every future launch — it will just
                // run with an empty/unavailable document list instead.
                return
            }

            // Store is corrupted or incompatible — wipe it and start fresh
            // rather than bricking the app permanently for this user.
            do {
                try container.persistentStoreCoordinator.destroyPersistentStore(
                    at: storeURL, ofType: storeDescription.type, options: nil
                )
            } catch {
                try? FileManager.default.removeItem(at: storeURL)
            }
            loadStore(into: container, isRetry: true)
        }
    }

    func saveIfNeeded(in context: NSManagedObjectContext? = nil) {
        let ctx = context ?? container.viewContext
        guard ctx.hasChanges else {
            print("CoreData: no changes to save")
            return
        }
        do {
            try ctx.save()
            print("CoreData saved successfully")
        } catch {
            print("Core Data save error:", error)
        }
    }
}
