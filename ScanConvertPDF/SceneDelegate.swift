//
//  SceneDelegate.swift
//  ScanConvertPDF
//
//  Created by Developer on 19.01.2026.
//

import UIKit
import StoreKit

extension Notification.Name {
    static let ratingPromptEnabledDidChange  = Notification.Name("ratingPromptEnabledDidChange")
    static let onboardingProviderDidChange   = Notification.Name("onboardingProviderDidChange")
    static let paywallProviderDidChange      = Notification.Name("paywallProviderDidChange")
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // MARK: - Keys / Flags

    private enum Defaults {
        static let tutorialFinished = "tutorialFinished"
        static let hasSubmittedRating = "hasSubmittedRating"
        static let isFirstSessionAfterOnboarding = "isFirstSessionAfterOnboarding"
    }

    var window: UIWindow?

    private var ratingWindow: UIWindow?
    private var ratingPromptEnabled: Bool = true

    private var useAdaptyOnboarding: Bool = true
    private var useAdaptyPaywall: Bool = true

    private var ratingTimer: Timer?
    private let ratingDelay: TimeInterval = 30

    // MARK: - Scene

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {

        guard let windowScene = (scene as? UIWindowScene) else { return }

        // 1) Create root tab controller
        let tabController = buildRootTabController()

        // 2) Window
        let w = UIWindow(windowScene: windowScene)
        w.rootViewController = tabController
        w.makeKeyAndVisible()
        self.window = w

        // 3) Subscriptions to RC (optional)
        subscribeToRemoteConfigIfNeeded()

        // 4) Onboarding (if needed)
        presentOnboardingIfNeeded(from: tabController)

        // 5) Launch paywall will be shown on sceneDidBecomeActive
        // (skipped on first launch to avoid conflict with onboarding)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        let isFirstSession = UserDefaults.standard.bool(forKey: Defaults.isFirstSessionAfterOnboarding)
        if isFirstSession {
            UserDefaults.standard.set(false, forKey: Defaults.isFirstSessionAfterOnboarding)
        }
        
        if let rootVC = window?.rootViewController {
            Task {
                await SubscriptionManager.shared.updatePremiumStatus()
                await MainActor.run {
                    self.showLaunchPaywallIfNeeded(from: rootVC)
                }
            }
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        stopRatingTimer()

        // Clear first session flag so launch paywall can show on next session
        if UserDefaults.standard.bool(forKey: Defaults.isFirstSessionAfterOnboarding) {
            UserDefaults.standard.set(false, forKey: Defaults.isFirstSessionAfterOnboarding)
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        CoreDataStack.shared.saveIfNeeded()
    }

    deinit {
        stopRatingTimer()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Root builder

    private func buildRootTabController() -> RootTabBarController {
        let scansVC = MainViewController()
        scansVC.tabBarItem = UITabBarItem(
            title: "Scans",
            image: UIImage(systemName: "doc.viewfinder"),
            selectedImage: UIImage(systemName: "doc.viewfinder")
        )

        let settingsVC = SettingsViewController()
        settingsVC.tabBarItem = UITabBarItem(
            title: "Settings",
            image: UIImage(systemName: "gearshape"),
            selectedImage: UIImage(systemName: "gearshape.fill")
        )

        let scansNav = UINavigationController(rootViewController: scansVC)
        let settingsNav = UINavigationController(rootViewController: settingsVC)

        let tabController = RootTabBarController()

        tabController.transitionStyle = .crossDissolve
        tabController.popsToRootOnReselect = true
        tabController.scrollsToTopOnReselect = true

        tabController.tabBarTintColor = .systemRed
        tabController.tabBarUnselectedTintColor = .gray
        tabController.dockTabBar.tabbarColor = AppColors.cellBackground
        tabController.dockTabBar.centerButtonSize = 60
        tabController.dockTabBar.centerButtonColor = .systemRed
        tabController.dockTabBar.centerButtonImage = UIImage(systemName: "plus")
        tabController.dockTabBar.centerButtonImageSize = 20

        tabController.setupCenterButtonMenu(
            actions: [
                CenterMenuAction(title: "Scan", systemIcon: "doc.viewfinder") { [weak self, weak tabController] in
                    guard let self else { return }
                    guard let vc = self.topViewController(from: tabController) as? CenterMenuActionHandling else { return }
                    vc.handleCenterMenuAction(.scan)
                },
                CenterMenuAction(title: "Crop", systemIcon: "camera") { [weak self, weak tabController] in
                    guard let self else { return }
                    guard let vc = self.topViewController(from: tabController) as? CenterMenuActionHandling else { return }
                    vc.handleCenterMenuAction(.camera)
                },
                CenterMenuAction(title: "Gallery", systemIcon: "photo.on.rectangle") { [weak self, weak tabController] in
                    guard let self else { return }
                    guard let vc = self.topViewController(from: tabController) as? CenterMenuActionHandling else { return }
                    vc.handleCenterMenuAction(.gallery)
                },
                CenterMenuAction(title: "Folder", systemIcon: "folder.badge.plus") { [weak self, weak tabController] in
                    guard let self else { return }
                    guard let vc = self.topViewController(from: tabController) as? CenterMenuActionHandling else { return }
                    vc.handleCenterMenuAction(.folder)
                },
                CenterMenuAction(title: "Web Page", systemIcon: "globe") { [weak self, weak tabController] in
                    guard let self else { return }
                    guard let vc = self.topViewController(from: tabController) as? CenterMenuActionHandling else { return }
                    vc.handleCenterMenuAction(.webPage)
                },
                CenterMenuAction(title: "Documents", systemIcon: "doc.on.doc") { [weak self, weak tabController] in
                    guard let self else { return }
                    guard let vc = self.topViewController(from: tabController) as? CenterMenuActionHandling else { return }
                    vc.handleCenterMenuAction(.documents)
                }
            ],
            accentColor: AppColors.menuAccent
        )

        tabController.setViewControllers([scansNav, settingsNav], animated: false)
        tabController.selectedIndex = 0
        tabController.centerButtonDisabledTabs = [1]

        return tabController
    }

    private func topViewController(from root: UIViewController?) -> UIViewController? {
        guard let root else { return nil }

        if let tab = root as? RootTabBarController {
            let selected = tab.selectedViewController
            if let nav = selected as? UINavigationController { return nav.topViewController }
            return selected
        }

        if let nav = root as? UINavigationController { return nav.topViewController }
        return root
    }
}

// MARK: - Onboarding

extension SceneDelegate {

    private func presentOnboardingIfNeeded(from presenter: UIViewController) {
        guard !UserDefaults.standard.bool(forKey: Defaults.tutorialFinished) else { return }
        guard presenter.presentedViewController == nil else { return }

        if useAdaptyOnboarding {
            // Adapty onboarding
            let vc = AdaptyOnboardingViewController(
                placementID: AppConfig.Adapty.onboardingMainPlacementID
            ) { [weak self, weak presenter] result in
                guard let self, let presenter else { return }

                switch result {
                case .completedWithAdapty:
                    UserDefaults.standard.set(true, forKey: Defaults.tutorialFinished)
                    UserDefaults.standard.set(true, forKey: Defaults.isFirstSessionAfterOnboarding)

                    presenter.dismiss(animated: true) {
                        self.presentPaywallAfterOnboarding(from: presenter)
                    }

                case .completedWithFallback, .failed:
                    presenter.dismiss(animated: false) {
                        self.presentDefaultOnboarding(from: presenter)
                    }
                }
            }

            vc.modalPresentationStyle = .fullScreen
            presenter.present(vc, animated: true)
        } else {
            presentDefaultOnboarding(from: presenter)
        }
    }

    private func presentDefaultOnboarding(from presenter: UIViewController) {
        let onboardingVC = DefaultOnboardingViewController()
        onboardingVC.modalPresentationStyle = .fullScreen

        onboardingVC.onComplete = { [weak self, weak presenter] in
            guard let self, let presenter else { return }

            UserDefaults.standard.set(true, forKey: Defaults.tutorialFinished)
            UserDefaults.standard.set(true, forKey: Defaults.isFirstSessionAfterOnboarding)

            presenter.dismiss(animated: true) {
                self.presentPaywallAfterOnboarding(from: presenter)
            }
        }

        presenter.present(onboardingVC, animated: true)
    }
}

// MARK: - Paywall

extension SceneDelegate {
    
    /// Shows launch paywall if Remote Config allows
    private func showLaunchPaywallIfNeeded(from presenter: UIViewController) {
        guard RemoteConfigManager.shared.showPaywallOnLaunch else {
            print("[Paywall] Launch paywall disabled by Remote Config")
            startRatingTimerIfNeeded()
            return
        }
        
        guard !SubscriptionManager.shared.isPremiumActive else {
            print("[Paywall] User is premium, skipping launch paywall")
            startRatingTimerIfNeeded()
            return
        }
        
        guard UserDefaults.standard.bool(forKey: Defaults.tutorialFinished) else {
            print("[Paywall] Tutorial not finished, skipping launch paywall")
            startRatingTimerIfNeeded()
            return
        }
        
        // Don't show in the first session after onboarding
        guard !UserDefaults.standard.bool(forKey: Defaults.isFirstSessionAfterOnboarding) else {
            print("[Paywall] First session after onboarding, skipping launch paywall")
            startRatingTimerIfNeeded()
            return
        }
        
        guard presenter.presentedViewController == nil else {
            print("[Paywall] Another VC is presented, skipping launch paywall")
            startRatingTimerIfNeeded()
            return
        }
        
        print("[Paywall] Showing launch paywall")
        
        if useAdaptyPaywall {
            presentAdaptyLaunchPaywall(from: presenter)
        } else {
            presentStoreKitLaunchPaywall(from: presenter)
        }
    }
    
    private func presentAdaptyLaunchPaywall(from presenter: UIViewController) {
        let paywallVC = AdaptyPaywallViewController(
            placementID: AppConfig.Adapty.paywallLaunchPlacementID
        )
        
        paywallVC.onComplete = { [weak self, weak presenter] result in
            guard let self, let presenter else { return }
            
            switch result {
            case .loadingError(let error):
                print("[Paywall] Launch paywall - loading error: \(error.localizedDescription)")
                print("[Paywall] Falling back to StoreKit paywall")
                presenter.dismiss(animated: false) {
                    self.presentStoreKitLaunchPaywall(from: presenter)
                }
                
            case .skipped:
                print("[Paywall] Launch paywall - skipped (timeout)")
                print("[Paywall] Falling back to StoreKit paywall")
                presenter.dismiss(animated: false) {
                    self.presentStoreKitLaunchPaywall(from: presenter)
                }
                
            case .purchased, .restored:
                print("[Paywall] Launch paywall - user subscribed")
                presenter.dismiss(animated: true) {
                    self.startRatingTimerIfNeeded()
                }
                
            case .dismissed:
                print("[Paywall] Launch paywall - dismissed by user")
                presenter.dismiss(animated: true) {
                    self.startRatingTimerIfNeeded()
                }
                
            case .purchaseError(let error):
                print("[Paywall] Launch paywall - purchase error: \(error.localizedDescription)")
                // Keep paywall open so user can retry
                break
            }
        }
        
        paywallVC.modalPresentationStyle = .fullScreen
        presenter.present(paywallVC, animated: true)
    }
    
    private func presentStoreKitLaunchPaywall(from presenter: UIViewController) {
        let vc = StoreKitPaywallViewController()
        vc.modalPresentationStyle = .fullScreen
        
        vc.onClose = { [weak self, weak presenter] in
            print("[Paywall] StoreKit launch paywall - closed")
            presenter?.dismiss(animated: true) {
                self?.startRatingTimerIfNeeded()
            }
        }
        
        vc.onPurchaseSuccess = { [weak self, weak presenter] in
            print("[Paywall] StoreKit launch paywall - purchased")
            presenter?.dismiss(animated: true) {
                self?.startRatingTimerIfNeeded()
            }
        }
        
        presenter.present(vc, animated: true)
    }

    private func presentPaywallAfterOnboarding(from presenter: UIViewController) {
        guard !SubscriptionManager.shared.isPremiumActive else { return }

        if useAdaptyPaywall {
            let paywallVC = AdaptyPaywallViewController(
                placementID: AppConfig.Adapty.paywallAfterOnboardingPlacementID
            )

            paywallVC.onComplete = { [weak self, weak presenter] result in
                guard let self, let presenter else { return }

                switch result {
                case .loadingError(let error):
                    print("[Paywall] After onboarding - loading error: \(error.localizedDescription)")
                    print("[Paywall] Falling back to StoreKit paywall")
                    presenter.dismiss(animated: false) {
                        self.presentStoreKitPaywall(from: presenter)
                    }
                    
                case .skipped:
                    print("[Paywall] After onboarding - skipped (timeout)")
                    print("[Paywall] Falling back to StoreKit paywall")
                    presenter.dismiss(animated: false) {
                        self.presentStoreKitPaywall(from: presenter)
                    }
                    
                case .purchased, .restored:
                    print("[Paywall] After onboarding - user subscribed")
                    presenter.dismiss(animated: true) {
                        self.startRatingTimerIfNeeded()
                    }
                    
                case .dismissed:
                    print("[Paywall] After onboarding - dismissed by user")
                    presenter.dismiss(animated: true) {
                        self.startRatingTimerIfNeeded()
                    }
                    
                case .purchaseError(let error):
                    print("[Paywall] After onboarding - purchase error: \(error.localizedDescription)")
                    // Keep paywall open so user can retry
                    break
                }
            }

            paywallVC.modalPresentationStyle = .fullScreen
            presenter.present(paywallVC, animated: true)

        } else {
            presentStoreKitPaywall(from: presenter)
        }
    }

    private func presentStoreKitPaywall(from presenter: UIViewController) {
        let vc = StoreKitPaywallViewController()
        vc.modalPresentationStyle = .fullScreen

        vc.onClose = { [weak self, weak presenter] in
            presenter?.dismiss(animated: true) {
                self?.startRatingTimerIfNeeded()
            }
        }

        vc.onPurchaseSuccess = { [weak self, weak presenter] in
            presenter?.dismiss(animated: true) {
                self?.startRatingTimerIfNeeded()
            }
        }

        presenter.present(vc, animated: true)
    }
}

// MARK: - Rating prompt (overlay + timer)

extension SceneDelegate {

    private func startRatingTimerIfNeeded() {
        guard ratingPromptEnabled == true else { return }
        guard UserDefaults.standard.bool(forKey: Defaults.tutorialFinished) else { return }

        // Не показуємо в першу сесію після онбордингу
        if UserDefaults.standard.bool(forKey: Defaults.isFirstSessionAfterOnboarding) {
            return
        }

        guard !UserDefaults.standard.bool(forKey: Defaults.hasSubmittedRating) else { return }
        guard ratingTimer == nil else { return }

        ratingTimer = Timer.scheduledTimer(timeInterval: ratingDelay,
                                           target: self,
                                           selector: #selector(ratingTimerFired),
                                           userInfo: nil,
                                           repeats: false)
    }

    private func stopRatingTimer() {
        ratingTimer?.invalidate()
        ratingTimer = nil
    }

    @objc private func ratingTimerFired() {
        Task { @MainActor in
            self.showRatingPromptOverlay()
        }
    }

    @MainActor
    private func showRatingPromptOverlay() {
        guard ratingPromptEnabled == true else { return }
        guard UserDefaults.standard.bool(forKey: Defaults.tutorialFinished) else { return }
        guard !UserDefaults.standard.bool(forKey: Defaults.isFirstSessionAfterOnboarding) else { return }
        guard !UserDefaults.standard.bool(forKey: Defaults.hasSubmittedRating) else { return }

        guard let root = window?.rootViewController,
              root.presentedViewController == nil else { return }

        stopRatingTimer()

        guard let windowScene = window?.windowScene else { return }

        let rw = UIWindow(windowScene: windowScene)
        rw.windowLevel = .alert + 2
        rw.backgroundColor = .clear

        let rootVC = UIViewController()
        rootVC.view.backgroundColor = .clear
        rw.rootViewController = rootVC
        rw.makeKeyAndVisible()
        self.ratingWindow = rw

        let ratingVC = RateAppViewController(
            initialRating: 5,
            onSubmit: { [weak self] rating in
                UserDefaults.standard.set(true, forKey: Defaults.hasSubmittedRating)
                self?.dismissRatingOverlay()
            },
            onDismiss: { [weak self] in
                self?.dismissRatingOverlay()
            }
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            rootVC.present(ratingVC, animated: true)
        }
    }

    @MainActor
    private func dismissRatingOverlay() {
        UIView.animate(withDuration: 0.25, animations: {
            self.ratingWindow?.alpha = 0
        }) { _ in
            self.ratingWindow?.isHidden = true
            self.ratingWindow?.rootViewController = nil
            self.ratingWindow = nil
            self.window?.makeKeyAndVisible()
        }
    }
}

// MARK: - Remote Config subscriptions (optional)

extension SceneDelegate {

    private func subscribeToRemoteConfigIfNeeded() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleRatingPromptFlagChanged(_:)),
                                               name: .ratingPromptEnabledDidChange,
                                               object: nil)
    }

    @objc private func handleRatingPromptFlagChanged(_ notification: Notification) {
        guard let isEnabled = notification.userInfo?["value"] as? Bool else { return }
        ratingPromptEnabled = isEnabled

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if isEnabled {
                if let root = self.window?.rootViewController,
                   root.presentedViewController != nil {
                    return
                }
                self.startRatingTimerIfNeeded()
            } else {
                self.stopRatingTimer()
            }
        }
    }
}
