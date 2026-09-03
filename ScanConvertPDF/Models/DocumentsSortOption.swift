//
//  DocumentsSortOption.swift
//  ScanConvertPDF
//
//  Created by Developer on 20.01.2026.
//

import Foundation

// MARK: - App Settings

enum DocumentsSortOption: String, CaseIterable {
    case nameAZ
    case nameZA
    case dateNewest
    case dateOldest
}

final class AppSettings {
    static let shared = AppSettings()
    private init() {}

    private let defaults = UserDefaults.standard

    private enum Key {
        static let documentsSortOption = "documentsSortOption"
        static let darkMode = "app.settings.darkMode"
        static let isSubmittedRating = "isSubmittedRating"
    }

    var documentsSortOption: DocumentsSortOption {
        get {
            guard let raw = defaults.string(forKey: Key.documentsSortOption),
                  let value = DocumentsSortOption(rawValue: raw) else {
                return .dateNewest
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.documentsSortOption)
        }
    }
    
    var isDarkModeEnabled: Bool {
        get {
            return defaults.bool(forKey: Key.darkMode)
        }
        set {
            defaults.set(newValue, forKey: Key.darkMode)
        }
    }
    
    var isSubmittedRating: Bool {
        get {
            return defaults.bool(forKey: Key.isSubmittedRating)
        }
        set {
            defaults.set(newValue, forKey: Key.isSubmittedRating)
        }
    }
}
