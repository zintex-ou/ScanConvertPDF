//
//  Extension+UIImage.swift
//  ScanConvertPDF
//
//  Created by Developer on 22.01.2026.
//

import UIKit

// MARK: - UIImage helpers
extension UIImage {
    
    func normalizedImage() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}
