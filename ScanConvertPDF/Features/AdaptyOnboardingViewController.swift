//
//  AdaptyOnboardingViewController.swift
//  ScanConvertPDF
//
//  Created by Developer on 22.01.2026.
//

import UIKit
import Adapty
import AdaptyUI
import UserNotifications
import Network

enum OnboardingResult {
    case completedWithAdapty
    case completedWithFallback
    case failed(Error)
}

final class AdaptyOnboardingViewController: UIViewController {

    private let placementID: String
    private var onboardingController: AdaptyOnboardingController?
    private let onComplete: (OnboardingResult) -> Void

    private let networkMonitor = NWPathMonitor()

    // Таймаути
    private let loadingTimeout: TimeInterval = 10.0   // загальний таймаут на fetch+config+create
    private let displayTimeout: TimeInterval = 5.0    // якщо controller створився, але didFinishLoading не прийшов

    private var loadingTimeoutWorkItem: DispatchWorkItem?
    private var displayTimeoutWorkItem: DispatchWorkItem?

    private var isOnboardingLoaded = false
    private var isCompleted = false

    /// Важливо: якщо fallback вже показаний — ігноруємо пізні відповіді від Adapty
    private var isFallbackShown = false

    private lazy var loadingView: UIView = {
        let view = UIView()
        view.backgroundColor = .black

        let activityIndicator = UIActivityIndicatorView(style: .large)
        activityIndicator.color = .gray
        activityIndicator.startAnimating()
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }()

    init(placementID: String, onComplete: @escaping (OnboardingResult) -> Void) {
        self.placementID = placementID
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        showLoadingPlaceholder()
        checkNetworkAndLoad()
    }

    deinit {
        cancelAllTimeouts()
        networkMonitor.cancel()
    }

    // MARK: - Network

    private func checkNetworkAndLoad() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }

            DispatchQueue.main.async {
                if path.status == .satisfied {
                    self.loadAdaptyOnboarding()
                } else {
                    self.finishWithFallback()
                }
                self.networkMonitor.cancel()
            }
        }

        networkMonitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
    }

    // MARK: - Loading UI

    private func showLoadingPlaceholder() {
        loadingView.frame = view.bounds
        loadingView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(loadingView)
    }

    private func hideLoadingPlaceholder() {
        UIView.animate(withDuration: 0.3) {
            self.loadingView.alpha = 0
        } completion: { _ in
            self.loadingView.removeFromSuperview()
        }
    }

    // MARK: - Timeouts

    private func startLoadingTimeout() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isCompleted, !self.isOnboardingLoaded, !self.isFallbackShown else { return }
            self.finishWithFallback()
        }

        loadingTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + loadingTimeout, execute: item)
    }

    private func startDisplayTimeout() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isCompleted, !self.isOnboardingLoaded, !self.isFallbackShown else { return }
            self.finishWithFallback()
        }

        displayTimeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + displayTimeout, execute: item)
    }

    private func cancelAllTimeouts() {
        loadingTimeoutWorkItem?.cancel()
        loadingTimeoutWorkItem = nil
        displayTimeoutWorkItem?.cancel()
        displayTimeoutWorkItem = nil
    }

    // MARK: - Adapty

    private func loadAdaptyOnboarding() {
        guard !isCompleted, !isFallbackShown else { return }

        // 1) Загальний таймаут на завантаження
        startLoadingTimeout()

        Task { @MainActor in
            do {
                guard !self.isCompleted, !self.isFallbackShown else { return }

                let onboarding = try await Adapty.getOnboarding(placementId: placementID)
                guard !self.isCompleted, !self.isFallbackShown else { return }

                // якщо loading timeout вже спрацював (item cancelled / fallback shown) — стоп
                if let t = self.loadingTimeoutWorkItem, t.isCancelled { return }

                let configuration = try AdaptyUI.getOnboardingConfiguration(forOnboarding: onboarding)
                guard !self.isCompleted, !self.isFallbackShown else { return }

                let controller = try AdaptyUI.onboardingController(with: configuration, delegate: self)
                guard !self.isCompleted, !self.isFallbackShown else { return }

                self.onboardingController = controller

                addChild(controller)
                controller.view.frame = view.bounds
                controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                view.addSubview(controller.view)
                controller.didMove(toParent: self)

                // ❗️НЕ ховаємо loading тут — чекаємо didFinishLoading
                // 2) Додатковий таймаут якщо didFinishLoading не прийде
                self.startDisplayTimeout()

            } catch {
                // якщо вже fallback — ігноруємо
                guard !self.isCompleted, !self.isFallbackShown else { return }
                self.finishWithFallback() // (можна замінити на .failed(error) якщо хочеш)
            }
        }
    }

    // MARK: - Completion

    private func finishWithFallback() {
        guard !isCompleted else { return }

        // блок для пізніх callback-ів Adapty
        isFallbackShown = true
        isCompleted = true

        cancelAllTimeouts()
        removePartialAdaptyControllerIfNeeded()

        // якщо у тебе є свій Fallback VC — тут його показуй,
        // а onComplete викликай коли користувач завершить fallback.
        onComplete(.completedWithFallback)
    }

    private func finishWithSuccess() {
        guard !isCompleted else { return }

        isCompleted = true
        cancelAllTimeouts()

        onComplete(.completedWithAdapty)
    }

    private func removePartialAdaptyControllerIfNeeded() {
        guard let controller = onboardingController else { return }
        controller.willMove(toParent: nil)
        controller.view.removeFromSuperview()
        controller.removeFromParent()
        onboardingController = nil
    }
}

// MARK: - AdaptyOnboardingControllerDelegate

extension AdaptyOnboardingViewController: AdaptyOnboardingControllerDelegate {

    func onboardingController(_ controller: AdaptyOnboardingController, didFailWithError error: AdaptyUIError) {
        guard !isFallbackShown, !isCompleted else { return }
        finishWithFallback()
    }

    func onboardingController(_ controller: AdaptyOnboardingController, didFinishLoading action: OnboardingsDidFinishLoadingAction) {
        guard !isFallbackShown, !isCompleted else { return }

        isOnboardingLoaded = true

        // зупиняємо таймаути
        cancelAllTimeouts()

        // тепер можна ховати loading
        hideLoadingPlaceholder()
    }

    func onboardingController(_ controller: AdaptyOnboardingController, onCloseAction action: AdaptyOnboardingsCloseAction) {
        guard !isFallbackShown else { return }
        finishWithSuccess()
    }

    func onboardingController(_ controller: AdaptyOnboardingController, onCustomAction action: AdaptyOnboardingsCustomAction) {
        switch action.actionId {
        case "request_notifications":
            break
        case "request_tracking":
            break // ATT request if needed
        default:
            break
        }
    }

    func onboardingController(_ controller: AdaptyOnboardingController, onAnalyticsEvent event: AdaptyOnboardingsAnalyticsEvent) { }
    func onboardingController(_ controller: AdaptyOnboardingController, onStateUpdatedAction action: AdaptyOnboardingsStateUpdatedAction) { }
    func onboardingController(_ controller: AdaptyOnboardingController, onPaywallAction action: AdaptyOnboardingsOpenPaywallAction) { }
}
