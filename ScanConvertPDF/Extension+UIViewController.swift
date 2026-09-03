//
//  Extension+UIViewController.swift
//  ScanConvertPDF
//
//  Created by Developer on 19.01.2026.
//

import UIKit

extension UIViewController {
    var rootTabBarController: RootTabBarController? {
        var parent = parent
        while parent != nil {
            if let tab = parent as? RootTabBarController { return tab }
            parent = parent?.parent
        }
        return nil
    }
}
