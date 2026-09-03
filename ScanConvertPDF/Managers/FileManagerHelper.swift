//
//  FileManagerHelper.swift
//  ScanConvertPDF
//
//  Created by Developer
//

import UIKit
import PDFKit

class FileManagerHelper {
    
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    static var pdfDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("PDFs", isDirectory: true)
        createDirectoryIfNeeded(at: url)
        return url
    }
    
    static var thumbnailsDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
        createDirectoryIfNeeded(at: url)
        return url
    }
    
    private static func createDirectoryIfNeeded(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - PDF Operations
    
    static func savePDF(data: Data, fileName: String) -> URL? {
        let fileURL = pdfDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Error saving PDF: \(error)")
            return nil
        }
    }
    
    static func savePDF(document: PDFDocument, fileName: String) -> URL? {
        let fileURL = pdfDirectory.appendingPathComponent(fileName)
        if document.write(to: fileURL) {
            return fileURL
        }
        return nil
    }
    
    static func loadPDF(fileName: String) -> PDFDocument? {
        let fileURL = pdfDirectory.appendingPathComponent(fileName)
        return PDFDocument(url: fileURL)
    }
    
    static func deletePDF(fileName: String) {
        let fileURL = pdfDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Thumbnail Operations
    
    static func saveThumbnail(_ image: UIImage, fileName: String) -> URL? {
        let fileURL = thumbnailsDirectory.appendingPathComponent(fileName)
        guard let data = image.jpegData(compressionQuality: 0.7) else { return nil }
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Error saving thumbnail: \(error)")
            return nil
        }
    }
    
    static func loadThumbnail(fileName: String) -> UIImage? {
        let fileURL = thumbnailsDirectory.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: fileURL.path)
    }
    
    static func deleteThumbnail(fileName: String) {
        let fileURL = thumbnailsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Generate Thumbnail from PDF
    
    static func generateThumbnail(from pdfDocument: PDFDocument, size: CGSize = CGSize(width: 200, height: 280)) -> UIImage? {
        guard let page = pdfDocument.page(at: 0) else { return nil }
        
        let pageRect = page.bounds(for: .mediaBox)
        let scale = min(size.width / pageRect.width, size.height / pageRect.height)
        let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let renderer = UIGraphicsImageRenderer(size: scaledSize)
        let thumbnail = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: scaledSize))
            
            context.cgContext.translateBy(x: 0, y: scaledSize.height)
            context.cgContext.scaleBy(x: scale, y: -scale)
            
            page.draw(with: .mediaBox, to: context.cgContext)
        }
        
        return thumbnail
    }
    
    // MARK: - Create PDF from Images
    
    static func createPDF(from images: [UIImage]) -> PDFDocument? {
        let pdfDocument = PDFDocument()
        for (index, image) in images.enumerated() {
            guard let pdfPage = PDFPage(image: image) else { continue }
            pdfDocument.insert(pdfPage, at: index)
        }
        return pdfDocument.pageCount > 0 ? pdfDocument : nil
    }
    
    // MARK: - Unique File Name
    
    static func uniqueFileName(extension ext: String) -> String {
        let timestamp = Date().timeIntervalSince1970
        let uuid = UUID().uuidString.prefix(8)
        return "\(Int(timestamp))_\(uuid).\(ext)"
    }
}
