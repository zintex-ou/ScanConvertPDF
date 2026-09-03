//
//  SubscriptionManager.swift
//  ScanConvertPDF
//
//  Created by Developer on 22.01.2026.
//

import UIKit
import StoreKit
import Adapty
import AdaptyUI
import Combine


// MARK: - PaywallResult

public enum PaywallResult {
    case purchased
    case restored
    case dismissed
    case skipped
    case loadingError(Error)
    case purchaseError(Error)

    init(from paywallVCResult: PaywallResult) {
        switch paywallVCResult {
        case .purchased:
            self = .purchased
        case .restored:
            self = .restored
        case .dismissed:
            self = .dismissed
        case .skipped:
            self = .skipped
        case .loadingError(let error):
            self = .loadingError(error)
        case .purchaseError(let error):
            self = .purchaseError(error)
        }
    }
}

// MARK: - Protocol

public protocol SubscriptionManaging: AnyObject {
    var isPremiumActive: Bool { get }
    var isPremiumActivePublisher: AnyPublisher<Bool, Never> { get }
    var isLoading: Bool { get }
    var isReady: Bool { get }

    func initialize() async
    func updatePremiumStatus() async
    func restorePurchases() async -> Bool
    func getConfiguration(for placementID: String) async throws -> AdaptyUI.PaywallConfiguration
    func clearCache()
}

// MARK: - SubscriptionManager

public final class SubscriptionManager: ObservableObject, SubscriptionManaging {

    public static let shared = SubscriptionManager()

    @Published public private(set) var isPremiumActive: Bool = false {
        didSet {
            premiumStatusSubject.send(isPremiumActive)
            UserDefaults.standard.set(isPremiumActive, forKey: Keys.isPremiumActive)
        }
    }

    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isReady: Bool = false

    private let premiumStatusSubject = CurrentValueSubject<Bool, Never>(false)

    public var isPremiumActivePublisher: AnyPublisher<Bool, Never> {
        premiumStatusSubject
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    private var configurationCache: [String: CachedConfiguration] = [:]
    private let cacheQueue = DispatchQueue(label: "com.unibox.cache", attributes: .concurrent)
    private var cancellables = Set<AnyCancellable>()

    private enum Keys {
        static let isPremiumActive = "isPremiumActive"
    }

    private enum SMConfig {
        static let maxRetryAttempts = 3
        static let retryDelay: TimeInterval = 1.0
        static let loadTimeout: TimeInterval = 5.0
        static let cacheExpirationInterval: TimeInterval = 300
    }

    private struct CachedConfiguration {
        let configuration: AdaptyUI.PaywallConfiguration
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > SMConfig.cacheExpirationInterval
        }
    }

    private init() {
        isPremiumActive = UserDefaults.standard.bool(forKey: Keys.isPremiumActive)
        premiumStatusSubject.send(isPremiumActive)
    }

    // MARK: - Init / Bootstrap

    public func initialize() async {
        guard !isReady else { return }

        do {
            try await withTimeout(seconds: 5.0) {
                try await AdaptyUI.activate(configuration: .default)
            }
        } catch {
            // optional: log
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.preloadConfiguration(for: AppConfig.Adapty.paywallAfterOnboardingPlacementID)
            }
            group.addTask {
                await self.preloadConfiguration(for: AppConfig.Adapty.paywallMainPlacementID)
            }

            let deadline = Date().addingTimeInterval(10.0)
            while Date() < deadline {
                if await group.next() == nil { break }
            }
            group.cancelAll()
        }

        await updatePremiumStatus()

        await MainActor.run {
            self.isReady = true
        }
    }

    // MARK: - Premium status

    public func updatePremiumStatus() async {
        do {
            let profile = try await withTimeout(seconds: 10.0) {
                try await self.withRetry(attempts: 2) {
                    try await Adapty.getProfile()
                }
            }

            let newStatus = profile.accessLevels["premium"]?.isActive ?? false
            self.isPremiumActive = newStatus

        } catch is TimeoutError {
            // optional: log
        } catch {
            // optional: log
        }
    }

    // MARK: - Restore

    @discardableResult
    public func restorePurchases() async -> Bool {
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let profile = try await withRetry {
                try await Adapty.restorePurchases()
            }

            let isPremium = profile.accessLevels["premium"]?.isActive ?? false

            await MainActor.run {
                self.isPremiumActive = isPremium
            }

            return isPremium

        } catch {
            return false
        }
    }

    // MARK: - Paywall configuration

    public func getConfiguration(for placementID: String) async throws -> AdaptyUI.PaywallConfiguration {
        if let cached = getCachedConfiguration(for: placementID), !cached.isExpired {
            return cached.configuration
        }

        let configuration = try await withRetry {
            let paywall = try await Adapty.getPaywall(placementId: placementID, locale: "en")
            let products = try await Adapty.getPaywallProducts(paywall: paywall)

            let config = try await AdaptyUI.getPaywallConfiguration(
                forPaywall: paywall,
                loadTimeout: SMConfig.loadTimeout,
                products: products
            )

            try? await Adapty.logShowPaywall(paywall)

            return config
        }

        setCachedConfiguration(configuration, for: placementID)
        return configuration
    }

    public func clearCache() {
        cacheQueue.async(flags: .barrier) {
            self.configurationCache.removeAll()
        }
    }

    public func reloadConfiguration(for placementID: String) async {
        removeCachedConfiguration(for: placementID)
        await preloadConfiguration(for: placementID)
    }

    public func reloadAllConfigurations() async {
        clearCache()

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.preloadConfiguration(for: AppConfig.Adapty.paywallAfterOnboardingPlacementID) }
            group.addTask { await self.preloadConfiguration(for: AppConfig.Adapty.paywallMainPlacementID) }
        }
    }

    public func getSubscriptionInfo() async -> AdaptyProfile? {
        do {
            return try await withRetry {
                try await Adapty.getProfile()
            }
        } catch {
            return nil
        }
    }

    // MARK: - Preload

    private func preloadConfiguration(for placementID: String) async {
        do {
            let paywall = try await Adapty.getPaywall(placementId: placementID, locale: "en")
            let products = try await Adapty.getPaywallProducts(paywall: paywall)

            let configuration = try await AdaptyUI.getPaywallConfiguration(
                forPaywall: paywall,
                loadTimeout: SMConfig.loadTimeout,
                products: products
            )

            setCachedConfiguration(configuration, for: placementID)
            try? await Adapty.logShowPaywall(paywall)

        } catch {
            // optional: log
        }
    }

    // MARK: - Cache

    private func getCachedConfiguration(for placementID: String) -> CachedConfiguration? {
        cacheQueue.sync {
            configurationCache[placementID]
        }
    }

    private func setCachedConfiguration(_ configuration: AdaptyUI.PaywallConfiguration, for placementID: String) {
        cacheQueue.async(flags: .barrier) {
            self.configurationCache[placementID] = CachedConfiguration(
                configuration: configuration,
                timestamp: Date()
            )
        }
    }

    private func removeCachedConfiguration(for placementID: String) {
        cacheQueue.async(flags: .barrier) {
            self.configurationCache.removeValue(forKey: placementID)
        }
    }

    // MARK: - Retry

    private func withRetry<T>(
        attempts: Int = SMConfig.maxRetryAttempts,
        delay: TimeInterval = SMConfig.retryDelay,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...attempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                if attempt < attempts {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? NSError(domain: "SubscriptionManager", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Operation failed after \(attempts) attempts"
        ])
    }
}

// MARK: - Presentation

extension SubscriptionManager {

    public func presentPaywall(
        placementID: String,
        from viewController: UIViewController,
        animated: Bool = true,
        completion: ((PaywallResult) -> Void)? = nil
    ) {
        let paywallVC = AdaptyPaywallViewController(
            placementID: placementID,
            subscriptionManager: self
        )

        paywallVC.onComplete = { [weak paywallVC] result in
            _ = Self.convertPaywallResult(result)

            paywallVC?.dismiss(animated: animated) {
                completion?(result)
            }
        }

        paywallVC.modalPresentationStyle = .fullScreen
        paywallVC.modalTransitionStyle = .crossDissolve
        viewController.present(paywallVC, animated: animated)
    }

    public func presentPaywallAsRoot(
        placementID: String,
        in window: UIWindow?,
        completion: ((PaywallResult) -> Void)? = nil
    ) {
        guard let window = window else {
            completion?(.loadingError(NSError(
                domain: "SubscriptionManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Window is nil"]
            )))
            return
        }

        let paywallVC = AdaptyPaywallViewController(
            placementID: placementID,
            subscriptionManager: self
        )

        paywallVC.onComplete = { result in
            let managerResult = Self.convertPaywallResult(result)
            completion?(managerResult)
        }

        window.rootViewController = paywallVC
        window.makeKeyAndVisible()

        UIView.transition(
            with: window,
            duration: 0.3,
            options: .transitionCrossDissolve,
            animations: nil
        )
    }

    private static func convertPaywallResult(_ result: PaywallResult) -> PaywallResult {
        result
    }
}

// MARK: - Helpers / Observing

extension SubscriptionManager {

    public var canShowPaywall: Bool {
        isReady && !isLoading
    }

    public func checkPremiumStatus() {
        Task { await updatePremiumStatus() }
    }

    public func observePremiumStatus(_ handler: @escaping (Bool) -> Void) -> AnyCancellable {
        isPremiumActivePublisher
            .sink(receiveValue: handler)
    }
}

// MARK: - Timeout

extension SubscriptionManager {

    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError(seconds: seconds)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Paywall + StoreKit fallback

extension SubscriptionManager {

    public func presentPaywallWithFallback(
        placementID: String,
        from viewController: UIViewController,
        animated: Bool = true,
        completion: ((PaywallResult) -> Void)? = nil
    ) {
        let paywallVC = AdaptyPaywallViewController(
            placementID: placementID,
            subscriptionManager: self
        )

        paywallVC.onComplete = { [weak viewController] result in
            switch result {
            case .loadingError:
                viewController?.dismiss(animated: false) {
                    self.presentStoreKitFallback(from: viewController, completion: completion)
                }

            case .purchased, .restored, .dismissed, .skipped, .purchaseError:
                viewController?.dismiss(animated: animated) {
                    completion?(result)
                }
            }
        }

        paywallVC.modalPresentationStyle = .fullScreen
        viewController.present(paywallVC, animated: animated)
    }

    private func presentStoreKitFallback(
        from viewController: UIViewController?,
        completion: ((PaywallResult) -> Void)?
    ) {
        guard let viewController = viewController else { return }

        let storeKitPaywallVC = StoreKitPaywallViewController()
        storeKitPaywallVC.modalPresentationStyle = .fullScreen

        storeKitPaywallVC.onClose = {
            viewController.dismiss(animated: true) {
                completion?(.dismissed)
            }
        }

        storeKitPaywallVC.onPurchaseSuccess = {
            viewController.dismiss(animated: true) {
                completion?(.purchased)
            }
        }

        viewController.present(storeKitPaywallVC, animated: true)
    }
}

// MARK: - TimeoutError

struct TimeoutError: LocalizedError {
    let seconds: TimeInterval
    var errorDescription: String? {
        "Operation timed out after \(seconds) seconds"
    }
}
