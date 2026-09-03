//
//  RatingManager.swift
//  ScanConvertPDF
//

import Foundation

/*

final class RatingManager {
    static let shared = RatingManager()
    private init() {}

    private let minDaysBetweenPrompts = 30
    private let launchTriggers = [3, 10, 25, 50, 100]

    func incrementLaunch() {
        AppSettings.shared.appLaunchCount += 1
    }

    func shouldShowRating(userHasSubscription: Bool) -> Bool {
        guard !userHasSubscription else { return false }

        let count = AppSettings.shared.appLaunchCount
        guard launchTriggers.contains(count) else { return false }

        if let lastDate = AppSettings.shared.ratingLastSubmittedDate {
            let daysPassed = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            guard daysPassed >= minDaysBetweenPrompts else { return false }
        }

        return true
    }

    func markSubmitted() {
        AppSettings.shared.ratingLastSubmittedDate = Date()
    }
}

*/
