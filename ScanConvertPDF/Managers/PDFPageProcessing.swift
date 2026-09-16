//
//  PDFPageProcessing.swift
//  ScanConvertPDF
//
//  Shared helpers to rasterize PDF pages to images, apply a filter or
//  compression, and rebuild a PDFDocument from the result.
//

import UIKit
import CoreImage
import PDFKit

enum PDFFilterOption: CaseIterable, Equatable {
    case original
    case blackAndWhite
    case highContrast

    var title: String {
        switch self {
        case .original: return "Original (Remove Filter)"
        case .blackAndWhite: return "Black & White"
        case .highContrast: return "High Contrast"
        }
    }
}

enum PDFCompressionLevel: CaseIterable {
    case best
    case balanced
    case small

    var title: String {
        switch self {
        case .best: return "Best Quality"
        case .balanced: return "Balanced"
        case .small: return "Smallest File Size"
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .best: return 0.8
        case .balanced: return 0.5
        case .small: return 0.3
        }
    }

    var maxDimension: CGFloat {
        switch self {
        case .best: return 2200
        case .balanced: return 1600
        case .small: return 1200
        }
    }
}

enum PDFPageProcessor {

    private static let ciContext = CIContext()

    /// Rasterizes a PDF page to a UIImage at its own point size (2x scale for sharpness).
    static func image(from page: PDFPage, scale: CGFloat = 2.0) -> UIImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)

        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: bounds.size))

            let cgContext = ctx.cgContext
            cgContext.translateBy(x: 0, y: bounds.size.height)
            cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: cgContext)
        }
    }

    static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Applies a color filter. `.original` returns the image unchanged.
    static func apply(_ filter: PDFFilterOption, to image: UIImage) -> UIImage {
        guard filter != .original, let ciImage = CIImage(image: image) else { return image }

        let output: CIImage?
        switch filter {
        case .original:
            output = ciImage

        case .blackAndWhite:
            let mono = CIFilter(name: "CIColorMonochrome")
            mono?.setValue(ciImage, forKey: kCIInputImageKey)
            mono?.setValue(CIColor(color: .white), forKey: "inputColor")
            mono?.setValue(1.0, forKey: "inputIntensity")
            output = mono?.outputImage

        case .highContrast:
            let controls = CIFilter(name: "CIColorControls")
            controls?.setValue(ciImage, forKey: kCIInputImageKey)
            controls?.setValue(1.35, forKey: "inputContrast")
            controls?.setValue(1.0, forKey: "inputSaturation")
            output = controls?.outputImage
        }

        guard let output,
              let cgImage = ciContext.createCGImage(output, from: output.extent) else {
            return image
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Recompresses through JPEG at the given quality/size to shrink file size.
    static func compress(_ image: UIImage, level: PDFCompressionLevel) -> UIImage {
        let resized = resize(image, maxDimension: level.maxDimension)
        guard let jpegData = resized.jpegData(compressionQuality: level.jpegQuality),
              let reloaded = UIImage(data: jpegData) else {
            return resized
        }
        return reloaded
    }

    static func document(from images: [UIImage]) -> PDFDocument? {
        let pdf = PDFDocument()
        for (index, image) in images.enumerated() {
            guard let page = PDFPage(image: image) else { continue }
            pdf.insert(page, at: index)
        }
        return pdf.pageCount > 0 ? pdf : nil
    }

    /// Rasterizes every page of `document`, applies `transform` to each page image,
    /// and rebuilds a new PDFDocument from the results.
    static func rebuild(_ document: PDFDocument, transform: (UIImage) -> UIImage) -> PDFDocument? {
        var images: [UIImage] = []
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i),
                  let rendered = image(from: page) else { continue }
            images.append(transform(rendered))
        }
        return self.document(from: images)
    }
}
