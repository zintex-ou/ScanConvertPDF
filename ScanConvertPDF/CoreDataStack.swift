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
        container.loadPersistentStores { storeDescription, error in
            if let error { fatalError("Core Data load error: \(error)") }

            print("CoreData store loaded:")
            print("type:", storeDescription.type)
            print("url:", storeDescription.url?.absoluteString ?? "nil")
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
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
