//
//  AdaptyPaywallViewController.swift
//  ScanConvertPDF
//
//  Created by Developer on 22.01.2026.
//


import UIKit
import Adapty
import AdaptyUI

class AdaptyPaywallViewController: UIViewController {
    
    private let placementID: String
    private let subscriptionManager: SubscriptionManaging
    private var paywallController: AdaptyPaywallController?
    private var loadingView: PaywallLoadingView?
    
    private let loadingTimeout: TimeInterval = 12.0
    private var loadingTimeoutWorkItem: DispatchWorkItem?
    private var isPaywallLoaded = false
    private var isCompleted = false
    
    var onComplete: ((PaywallResult) -> Void)?
    
    private enum State {
        case loading
        case loaded(AdaptyPaywallController)
        case error(Error)
        case completed
    }
    
    private var state: State = .loading {
        didSet {
            updateUI(for: state)
        }
    }
    
    init(placementID: String, subscriptionManager: SubscriptionManaging = SubscriptionManager.shared) {
        self.placementID = placementID
        self.subscriptionManager = subscriptionManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadPaywall()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if case .completed = state { return }
        paywallController = nil
    }
    
    deinit {
        loadingTimeoutWorkItem?.cancel()
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        loadingView = PaywallLoadingView()
        loadingView?.translatesAutoresizingMaskIntoConstraints = false
        
        if let loadingView = loadingView {
            view.addSubview(loadingView)
            
            NSLayoutConstraint.activate([
                loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                loadingView.topAnchor.constraint(equalTo: view.topAnchor),
                loadingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
    
    private func updateUI(for state: State) {
        switch state {
        case .loading:
            loadingView?.startAnimating()
            
        case .loaded:
            loadingView?.stopAnimating()
            
        case .error:
            loadingView?.stopAnimating()
            
        case .completed:
            loadingView?.stopAnimating()
        }
    }
    
    private func loadPaywall() {
        state = .loading
        
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isPaywallLoaded else { return }
            self.complete(with: .skipped)
        }
        self.loadingTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + loadingTimeout, execute: timeoutItem)
        
        Task { [weak self] in
            guard let self = self else { return }

            do {
                let configuration = try await self.subscriptionManager.getConfiguration(for: self.placementID)

                await MainActor.run {
                    // якщо таймаут вже завершив flow — НЕ показуємо paywall
                    guard !self.isCompleted else { return }

                    self.isPaywallLoaded = true
                    self.loadingTimeoutWorkItem?.cancel()
                    self.presentPaywall(with: configuration)
                }
            } catch {
                await MainActor.run {
                    guard !self.isCompleted else { return }
                    self.handleLoadingError(error)
                }
            }
        }
    }
    
    @MainActor
    private func presentPaywall(with configuration: AdaptyUI.PaywallConfiguration) {
        do {
            let controller = try AdaptyUI.paywallController(
                with: configuration,
                delegate: self,
                showDebugOverlay: false
            )
            
            self.paywallController = controller
            state = .loaded(controller)
            
            addChild(controller)
            controller.view.frame = view.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(controller.view)
            controller.didMove(toParent: self)
            
        } catch {
            handleLoadingError(error)
        }
    }
    
    private func complete(with result: PaywallResult) {
        guard !isCompleted else { return }

        isCompleted = true
        loadingTimeoutWorkItem?.cancel()
        state = .completed

        onComplete?(result)
    }
    
    private func handleLoadingError(_ error: Error) {
        state = .error(error)
        complete(with: .loadingError(error))
    }

    private func showSuccessAlert(title: String, message: String, result: PaywallResult) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            self?.complete(with: result)
        })
        
        let presenter = paywallController ?? self
        presenter.present(alert, animated: true)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak alert, weak self] in
            guard let alert = alert, alert.presentingViewController != nil else { return }
            alert.dismiss(animated: true) {
                self?.complete(with: result)
            }
        }
    }
    
    private func showPurchaseErrorAlert(error: Error) {
        let alert = UIAlertController(
            title: "Purchase Failed",
            message: "There was an error processing your purchase. Please try again.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        let presenter = paywallController ?? self
        presenter.present(alert, animated: true)
    }
    
    private func showPendingAlert() {
        let alert = UIAlertController(
            title: "Purchase Pending",
            message: "Your purchase is awaiting approval. Premium unlocks once it is approved.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "OK", style: .default))

        let presenter = paywallController ?? self
        presenter.present(alert, animated: true)
    }

    private func showNoSubscriptionAlert() {
        let alert = UIAlertController(
            title: "No Subscription Found",
            message: "We couldn't find any active subscriptions for your account.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        let presenter = paywallController ?? self
        presenter.present(alert, animated: true)
    }
    
    private func showRestoreErrorAlert(error: Error) {
        let alert = UIAlertController(
            title: "Restore Failed",
            message: "We couldn't restore your purchases. Please try again later.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        let presenter = paywallController ?? self
        presenter.present(alert, animated: true)
    }
}

extension AdaptyPaywallViewController: AdaptyPaywallControllerDelegate {
    
    func paywallControllerDidAppear(_ controller: AdaptyPaywallController) {}
    
    func paywallControllerDidDisappear(_ controller: AdaptyPaywallController) {}
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didPerform action: AdaptyUI.Action
    ) {
        switch action {
        case .close:
            complete(with: .dismissed)
            
        case .openURL(let url):
            openURL(url)
            
        case .custom:
            break
        }
    }
    
    private func openURL(_ url: URL) {
        guard UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:])
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didSelectProduct product: AdaptyPaywallProductWithoutDeterminingOffer
    ) {
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didStartPurchase product: AdaptyPaywallProduct
    ) {
        loadingView?.isHidden = false
        loadingView?.startAnimating()
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishPurchase product: AdaptyPaywallProduct,
        purchaseResult: AdaptyPurchaseResult
    ) {
        loadingView?.stopAnimating()

        // logPurchaseAnalytics

        // This delegate fires for every outcome, cancellation included. Without this switch
        // a cancelled purchase would be reported as .purchased and close the paywall.
        switch purchaseResult {
        case .userCancelled:
            return

        case .pending:
            showPendingAlert()
            return

        case .success:
            break

        @unknown default:
            return
        }

        Task { [weak self] in
            guard let self = self else { return }

            await self.subscriptionManager.updatePremiumStatus()

            await MainActor.run {
                if self.subscriptionManager.isPremiumActive {
                    self.showSuccessAlert(
                        title: "Welcome to Premium!",
                        message: "You now have access to all premium features.",
                        result: .purchased
                    )
                } else {
                    // The purchase succeeded but the profile has not caught up yet. Without
                    // this branch the paywall just sits there and the user taps Buy again.
                    self.showSuccessAlert(
                        title: "Purchase Complete",
                        message: "Your purchase went through. It can take a moment to activate — "
                            + "if premium is not available yet, tap Restore.",
                        result: .purchased
                    )
                }
            }
        }
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailPurchase product: AdaptyPaywallProduct,
        error: AdaptyError
    ) {
        loadingView?.stopAnimating()
        
        if error.adaptyErrorCode == .paymentCancelled {
            return
        }
        
        showPurchaseErrorAlert(error: error)
    }
    
    func paywallControllerDidStartRestore(_ controller: AdaptyPaywallController) {
        loadingView?.isHidden = false
        loadingView?.startAnimating()
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishRestoreWith profile: AdaptyProfile
    ) {
        loadingView?.stopAnimating()
        
        Task { [weak self] in
            guard let self = self else { return }
            
            await self.subscriptionManager.updatePremiumStatus()
            
            await MainActor.run {
                if self.subscriptionManager.isPremiumActive {
                    self.showSuccessAlert(
                        title: "Subscription Restored!",
                        message: "Your premium access has been restored.",
                        result: .restored
                    )
                } else {
                    self.showNoSubscriptionAlert()
                }
            }
        }
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRestoreWith error: AdaptyError
    ) {
        loadingView?.stopAnimating()
        showRestoreErrorAlert(error: error)
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailRenderingWith error: AdaptyUIError
    ) {
        loadingView?.stopAnimating()
        complete(with: .loadingError(error))
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didFailLoadingProductsWith error: AdaptyError
    ) -> Bool {
        complete(with: .loadingError(error))
        return true
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didPartiallyLoadProducts failedIds: [String]
    ) {
    }
    
    func paywallController(
        _ controller: AdaptyPaywallController,
        didFinishWebPaymentNavigation product: AdaptyPaywallProduct?,
        error: AdaptyError?
    ) {
    }
}

private final class PaywallLoadingView: UIView {
    
    private let activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .gray
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .black
        
        addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    
    func startAnimating() {
        isHidden = false
        activityIndicator.startAnimating()
    }
    
    func stopAnimating() {
        activityIndicator.stopAnimating()
        isHidden = true
    }
}

