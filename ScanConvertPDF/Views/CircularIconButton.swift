//
//  CircularIconButton.swift
//  ScanConvertPDF
//
//  Created by Developer on 20.01.2026.
//

import UIKit

final class CircularIconButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        clipsToBounds = true
    }
}
