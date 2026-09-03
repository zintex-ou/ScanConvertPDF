//
//  CenterMenuActionHandling.swift
//  ScanConvertPDF
//
//  Created by Developer on 19.01.2026.
//

import Foundation
import UIKit

enum CenterMenuActionType {
    case scan
    case camera
    case gallery
    case folder
    case webPage
    case documents
}

protocol CenterMenuActionHandling: AnyObject {
    func handleCenterMenuAction(_ action: CenterMenuActionType)
}
