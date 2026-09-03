//
//  AppColors.swift
//  ScanConvertPDF
//
//  Created by Developer
//

import UIKit

// MARK: - Colors

enum AppColors {

    // MARK: - Helpers

    /// Static (not dynamic) color from 0...255 values
    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> UIColor {
        UIColor(red: r / 255.0, green: g / 255.0, blue: b / 255.0, alpha: a)
    }

    /// Dynamic color (light/dark)
    private static func dynamic(light: UIColor, dark: UIColor) -> UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        }
    }

    // MARK: - Brand / Accent

    /// Primary brand/accent color
    static var primary: UIColor {
        // твій новий "індиго" акцент
        rgb(250, 50, 60) //  // #FA323C
    }

    // MARK: - Backgrounds / Surfaces

    /// Main app background
    static var background: UIColor {
        dynamic(
            light: rgb(248, 248, 250),
            dark:  rgb(28, 28, 30)       // #1C1C1E
        )
    }

    /// Light gray surface (як було)
    static var lightGray: UIColor {
        dynamic(
            light: rgb(245, 245, 247),
            dark: rgb(32, 34, 42)
        )
    }

    /// Inactive surface for unselected containers (твій new inactive)
    static var inactive: UIColor {
        dynamic(
            light: rgb(242, 245, 250),   // ~0.95,0.96,0.98
            dark: rgb(41, 46, 56)        // ~0.16,0.18,0.22
        )
    }

    // MARK: - Dark shades (як було, але теж можна зробити dynamic якщо треба)

    static var dark: UIColor {
        dynamic(
            light: rgb(30, 30, 30),
            dark: rgb(10, 10, 12)
        )
    }

    static var darkGray: UIColor {
        dynamic(
            light: rgb(50, 50, 50),
            dark: rgb(235, 235, 235)
        )
    }

    // MARK: - Text

    static var textPrimary: UIColor {
        dynamic(
            light: rgb(30, 30, 30), // #1E1E1E
            dark: UIColor(white: 1.0, alpha: 0.92)
        )
    }

    static var textSecondary: UIColor {
        dynamic(
            light: UIColor(white: 0.0, alpha: 0.6),
            dark: UIColor(white: 1.0, alpha: 0.6)
        )
    }
    
    /// Cell background
    static var cellBackground: UIColor {
        dynamic(
            light: .white,
            dark: rgb(44, 44, 44) // #2C2C2E
        )
    }
    
    static var cellBackgroundHighlighted: UIColor {
        dynamic(
            light: rgb(242, 242, 242),
            dark:  rgb(58, 58, 60)
        )
    }
    
    static var shadowColor: UIColor {
        dynamic(
            light: .gray,
            dark:  .clear
        )
    }
    
    static var menuAccent: UIColor {
        dynamic(light: .black, dark: .white)
    }
}

// MARK: - Fonts

enum AppFonts {
    static func bold(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .bold) }
    static func semibold(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .semibold) }
    static func medium(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .medium) }
    static func regular(_ size: CGFloat) -> UIFont { .systemFont(ofSize: size, weight: .regular) }
}

// MARK: - Constants

enum AppConstants {
    static let cornerRadius: CGFloat = 16
    static let smallCornerRadius: CGFloat = 12
    static let padding: CGFloat = 16
    static let smallPadding: CGFloat = 8
}
