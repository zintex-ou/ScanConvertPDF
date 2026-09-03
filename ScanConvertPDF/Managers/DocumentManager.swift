//
//  DocumentManager.swift
//  ScanConvertPDF
//
//  Created by Developer
//


import UIKit
import PDFKit
import CoreData

final class DocumentManager {

    static let shared = DocumentManager()

    private let context: NSManagedObjectContext = CoreDataStack.shared.context

    private(set) var documents: [CDDocument] = []
    private(set) var folders: [CDFolder] = []

    var onDataChanged: (() -> Void)?

    private init() {
        loadData()
    }

    // MARK: - Fetch / Cache

    func loadData() {
        folders = fetchFolders()
        // за замовчуванням кешимо “root” документи (без папки), як було раніше
        documents = getDocuments(for: nil)
        onDataChanged?()
    }

    private func fetchFolders() -> [CDFolder] {
        let request: NSFetchRequest<CDFolder> = CDFolder.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        do { return try context.fetch(request) }
        catch {
            print("CoreData fetchFolders error:", error)
            return []
        }
    }

    // MARK: - Documents Fetch

    func getDocuments(for folderId: UUID? = nil) -> [CDDocument] {
        let request: NSFetchRequest<CDDocument> = CDDocument.fetchRequest()

        if let folderId {
            request.predicate = NSPredicate(format: "folder.id == %@", folderId as CVarArg)
        } else {
            request.predicate = NSPredicate(format: "folder == nil")
        }

        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]

        do { return try context.fetch(request) }
        catch {
            print("CoreData getDocuments error:", error)
            return []
        }
    }

    func getAllDocuments() -> [CDDocument] {
        let request: NSFetchRequest<CDDocument> = CDDocument.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        do { return try context.fetch(request) }
        catch {
            print("CoreData getAllDocuments error:", error)
            return []
        }
    }

    // MARK: - Folder Helpers

    func folder(withId id: UUID) -> CDFolder? {
        let request: NSFetchRequest<CDFolder> = CDFolder.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        do { return try context.fetch(request).first }
        catch {
            print("CoreData folder(withId:) error:", error)
            return nil
        }
    }

    func getDocumentCount(for folder: CDFolder) -> Int {
        let request: NSFetchRequest<CDDocument> = CDDocument.fetchRequest()
        request.predicate = NSPredicate(format: "folder == %@", folder)
        do { return try context.count(for: request) }
        catch { return 0 }
    }

    // MARK: - Folder Operations

    @discardableResult
    func addFolder(_ folder: CDFolder) -> CDFolder {
        // якщо ти створюєш folder ззовні — просто сейв
        if folder.id == nil { folder.id = UUID() }
        if folder.createdAt == nil { folder.createdAt = Date() }
        CoreDataStack.shared.saveIfNeeded()
        loadData()
        return folder
    }

    @discardableResult
    func addFolder(name: String) -> CDFolder {
        let folder = CDFolder(context: context)
        folder.id = UUID()
        folder.createdAt = Date()
        folder.name = name

        CoreDataStack.shared.saveIfNeeded()
        loadData()
        return folder
    }

    func updateFolder(_ folder: CDFolder, newName: String? = nil) {
        if let newName, !newName.isEmpty {
            folder.name = newName
        }
        CoreDataStack.shared.saveIfNeeded()
        loadData()
    }

    /// Видаляє папку + всі документи в ній + їх PDF файли з диска.
    /// (CoreData Cascade видалить записи, але файли треба прибирати вручну)
    func deleteFolder(_ folder: CDFolder) {
        // 1) видалити файли документів
        let docsInFolder = getDocuments(for: folder.id)
        for doc in docsInFolder {
            if let fileName = doc.pdfFileName {
                FileManagerHelper.deletePDF(fileName: fileName)
            }
        }

        // 2) видалити папку (документи злетять Cascade)
        context.delete(folder)
        CoreDataStack.shared.saveIfNeeded()
        loadData()
    }

    // MARK: - Document Operations

    func updateDocument(_ document: CDDocument, newName: String? = nil) {
        if let newName, !newName.isEmpty {
            document.name = newName
        }
        document.updatedAt = Date()
        CoreDataStack.shared.saveIfNeeded()
        loadData()
    }

    func deleteDocument(_ document: CDDocument) {
        if let fileName = document.pdfFileName {
            FileManagerHelper.deletePDF(fileName: fileName)
        }
        context.delete(document)
        CoreDataStack.shared.saveIfNeeded()
        loadData()
    }

    func moveDocument(_ document: CDDocument, to folder: CDFolder?) {
        document.folder = folder
        document.updatedAt = Date()
        CoreDataStack.shared.saveIfNeeded()
        loadData()
    }

    // MARK: - Create Document from Images

    @discardableResult
    func createDocument(from images: [UIImage],
                        name: String,
                        folderId: UUID? = nil) -> CDDocument? {

        guard let pdfDocument = FileManagerHelper.createPDF(from: images) else { return nil }

        let pdfFileName = FileManagerHelper.uniqueFileName(extension: "pdf")
        guard let pdfURL = FileManagerHelper.savePDF(document: pdfDocument, fileName: pdfFileName) else { return nil }

        let doc = CDDocument(context: context)
        doc.id = UUID()
        doc.name = name
        doc.createdAt = Date()
        doc.updatedAt = doc.createdAt
        doc.pageCount = Int16(images.count)
        doc.pdfFileName = pdfFileName

        // sizeBytes
        if let size = try? FileManager.default.attributesOfItem(atPath: pdfURL.path)[.size] as? NSNumber {
            doc.sizeBytes = size.int64Value
        }

        // thumbnailData
        if let thumb = FileManagerHelper.generateThumbnail(from: pdfDocument),
           let data = thumb.jpegData(compressionQuality: 0.85) {
            doc.thumbnailData = data
        }

        // folder relationship
        if let folderId, let folder = folder(withId: folderId) {
            doc.folder = folder
        }

        CoreDataStack.shared.saveIfNeeded()
        loadData()
        return doc
    }

    // MARK: - Create Document from PDF Data

    @discardableResult
    func createDocument(from pdfData: Data,
                        name: String,
                        folderId: UUID? = nil,
                        sourceURL: String? = nil) -> CDDocument? {

        let pdfFileName = FileManagerHelper.uniqueFileName(extension: "pdf")
        guard let pdfURL = FileManagerHelper.savePDF(data: pdfData, fileName: pdfFileName) else { return nil }

        let doc = CDDocument(context: context)
        doc.id = UUID()
        doc.name = name
        doc.createdAt = Date()
        doc.updatedAt = doc.createdAt
        doc.pdfFileName = pdfFileName

        if let pdf = PDFDocument(data: pdfData) {
            doc.pageCount = Int16(pdf.pageCount)

            if let thumb = FileManagerHelper.generateThumbnail(from: pdf),
               let data = thumb.jpegData(compressionQuality: 0.85) {
                doc.thumbnailData = data
            }
        } else {
            doc.pageCount = 1
        }

        if let size = try? FileManager.default.attributesOfItem(atPath: pdfURL.path)[.size] as? NSNumber {
            doc.sizeBytes = size.int64Value
        }

        // якщо у тебе є поле sourceURL в CoreData — розкоментуй
        // doc.sourceURL = sourceURL

        if let folderId, let folder = folder(withId: folderId) {
            doc.folder = folder
        }

        CoreDataStack.shared.saveIfNeeded()
        loadData()
        return doc
    }

    // MARK: - Search

    func searchDocuments(query: String) -> [CDDocument] {
        let request: NSFetchRequest<CDDocument> = CDDocument.fetchRequest()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", trimmed)
        }

        request.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]

        do { return try context.fetch(request) }
        catch {
            print("CoreData searchDocuments error:", error)
            return []
        }
    }
}
