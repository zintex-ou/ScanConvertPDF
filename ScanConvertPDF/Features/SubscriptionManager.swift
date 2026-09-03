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
    private var transactionListener: Task<Void, Never>?
    private var storeKitSyncTask: Task<Bool, Never>?

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

        // AdaptyUI is activated in AppDelegate.setupAdapty(); activating it a second time
        // here just throws and silently drops the .default configuration.

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

            let adaptyAccess = profile.accessLevels["premium"]?.isActive ?? false

            if adaptyAccess {
                await MainActor.run { self.isPremiumActive = true }
            } else {
                // Adapty reports no access. Before locking the user out, verify against
                // StoreKit directly: a purchase made through the StoreKit fallback paywall
                // reaches Adapty only via App Store Server Notifications, which lag (or are
                // not configured at all). Trusting Adapty blindly here means a paying user
                // stays behind the paywall.
                let localAccess = await hasActiveStoreKitEntitlement()
                await MainActor.run { self.isPremiumActive = localAccess }
            }

        } catch is TimeoutError {
            // Network unavailable — keep the last known status.
        } catch {
            // Adapty is unreachable or was never activated. Fall back to StoreKit so a
            // paying user who reinstalled is not left behind the paywall; only upgrade,
            // never revoke on the strength of a failed call.
            if await hasActiveStoreKitEntitlement() {
                await MainActor.run { self.isPremiumActive = true }
            }
        }
    }

    // MARK: - StoreKit entitlements (fallback source of truth)

    /// True when StoreKit itself reports a live, non-revoked entitlement to one of this
    /// app's subscription products. Only the paywall's own product IDs count, so an
    /// unrelated non-consumable added later cannot silently grant premium.
    public func hasActiveStoreKitEntitlement() async -> Bool {
        let knownProductIds = Set(PaywallProducts.allProductIds)

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard knownProductIds.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration <= Date() { continue }

            return true
        }
        return false
    }

    /// Call after a purchase or restore made with raw StoreKit 2 (the fallback paywall).
    ///
    /// StoreKit is checked first because it answers instantly and offline, and because the
    /// fallback paywall only appears when Adapty is already unreachable — going to Adapty
    /// first would leave a paying user staring at a spinner through three retries. Adapty is
    /// reconciled in the background so the server side catches up.
    @discardableResult
    public func syncAfterStoreKitPurchase() async -> Bool {
        // A concurrent caller waits for the in-flight result instead of getting a stale
        // isPremiumActive — otherwise the paywall can report "could not activate premium"
        // while the sync it is racing with is about to succeed.
        if let inFlight = storeKitSyncTask {
            return await inFlight.value
        }

        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }

            let localAccess = await self.hasActiveStoreKitEntitlement()

            if localAccess {
                await MainActor.run { self.isPremiumActive = true }
            }

            // Push the receipt to Adapty so its profile catches up, then reconcile.
            // Adapty.restorePurchases() is called directly rather than through the
            // restorePurchases() wrapper, because that wrapper writes isPremiumActive
            // unconditionally and would briefly flip a paying user back to false.
            // updatePremiumStatus() already refuses to downgrade below StoreKit's answer.
            Task { [weak self] in
                guard let self else { return }
                _ = try? await Adapty.restorePurchases()
                await self.updatePremiumStatus()
            }

            return localAccess
        }

        storeKitSyncTask = task
        let result = await task.value
        storeKitSyncTask = nil

        return result
    }

    // MARK: - Transaction listener

    /// Observes transactions that arrive outside a paywall: Ask to Buy approvals, purchases
    /// made on another device, renewals and refunds.
    ///
    /// Order matters: sync first, finish second. syncAfterStoreKitPurchase pushes the receipt
    /// to Adapty, and finishing afterwards is safe because finish() removes the transaction
    /// from the unfinished queue but not from the receipt or from currentEntitlements — Adapty
    /// can still validate it server-side. Leaving it unfinished instead would make the App
    /// Store replay the purchase prompt on every launch whenever Adapty failed to activate.
    public func startTransactionListener() {
        guard transactionListener == nil else { return }

        transactionListener = Task.detached { [weak self] in
            for await update in Transaction.updates {
                switch update {
                case .verified(let transaction):
                    _ = await self?.syncAfterStoreKitPurchase()
                    await transaction.finish()

                case .unverified(let transaction, _):
                    // Grants nothing, but must still be finished or the App Store replays
                    // it on every launch forever.
                    await transaction.finish()
                }
            }
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

            // Adapty saying "no" is not proof there is no subscription — its profile can lag
            // behind a StoreKit purchase. Check StoreKit before revoking access.
            let hasAccess = isPremium ? true : await hasActiveStoreKitEntitlement()

            await MainActor.run {
                self.isPremiumActive = hasAccess
            }

            return hasAccess

        } catch {
            guard await hasActiveStoreKitEntitlement() else { return false }
            await MainActor.run { self.isPremiumActive = true }
            return true
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
