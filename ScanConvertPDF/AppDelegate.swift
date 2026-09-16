//
//  AppDelegate.swift
//  ScanConvertPDF
//
//  Improved AdSupport + Adapty + Firebase integration
//

import UIKit
import CoreData
import Adapty
import AdaptyUI
import StoreKit
import AppTrackingTransparency
import AdSupport
import Firebase
import FirebaseAnalytics
import AdServices

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: - One-time flags
    private var hasLinkedFirebaseToAdapty = false
    private var hasRequestedATT = false
    private var hasRunASAAttribution = false
    private var firebaseLinkAttempts = 0

    private let maxFirebaseLinkAttempts = 5
    private let firebaseLinkRetryDelay: TimeInterval = 1.0

    // MARK: - App Lifecycle

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        setupNavigationBarAppearance()

        // 1. Firebase is the first (so that the appInstanceID is ready as soon as possible)
        setupFirebase()

        // 2. Adapty — activate async, then bind Firebase ID
        Task { await setupAdapty() }

        // 3. We listen for activation for ATT ASA (once)
        observeActivation()

        // 4. Listen for StoreKit transactions that arrive outside the
        //    purchase-button flow (Ask to Buy approvals, renewals,
        //    purchases from another device) so premium status and
        //    transaction.finish() aren't missed.
        Task { await self.observeTransactionUpdates() }

        return true
    }

    private func observeTransactionUpdates() async {
        for await update in Transaction.updates {
            guard case .verified(let transaction) = update else { continue }
            await SubscriptionManager.shared.restorePurchases()
            await transaction.finish()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup: Firebase

    private func setupFirebase() {
        FirebaseApp.configure()
        Analytics.logEvent("app_open", parameters: ["source": "launch" as NSObject])
        print("[Firebase] Configured. Logged app_open.")

        Task {
            let success = await RemoteConfigManager.shared.bootstrap()
            print("[Firebase] Remote Config bootstrap: \(success ? "Yes" : "No")")
        }
    }

    // MARK: - Setup: Adapty

    @MainActor
    private func setupAdapty() async {
        do {
            let config = AdaptyConfiguration
                .builder(withAPIKey: AppConfig.Adapty.adaptyPublicSdkKey)
                .with(observerMode: false)
                .with(idfaCollectionDisabled: false)
                .build()

            try await Adapty.activate(with: config)
            try await AdaptyUI.activate()
            Adapty.delegate = self
            print("[Adapty] Activated")

            // Let's try to bind Firebase right away
            attemptLinkFirebaseToAdapty(reason: "post-activation")

        } catch {
            print("[Adapty] Activation failed: \(error)")
        }
    }

    // MARK: - Firebase → Adapty Integration (з retry)

    private func attemptLinkFirebaseToAdapty(reason: String) {
        guard !hasLinkedFirebaseToAdapty else { return }

        guard let instanceId = Analytics.appInstanceID() else {
            firebaseLinkAttempts += 1
            print("[Firebase] appInstanceID nil (\(reason)), attempt \(firebaseLinkAttempts)/\(maxFirebaseLinkAttempts)")

            guard firebaseLinkAttempts < maxFirebaseLinkAttempts else {
                print("[Firebase] Gave up linking Firebase to Adapty")
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + firebaseLinkRetryDelay) { [weak self] in
                self?.attemptLinkFirebaseToAdapty(reason: "retry")
            }
            return
        }

        Adapty.setIntegrationIdentifier(key: "firebase_app_instance_id", value: instanceId)
        hasLinkedFirebaseToAdapty = true
        print("[Adapty] firebase_app_instance_id: \(instanceId)")
    }

    // MARK: - Activation Observer

    private func observeActivation() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    // MARK: - App Became Active

    @objc private func handleAppDidBecomeActive() {
        // Retry to bind Firebase if not yet successful
        attemptLinkFirebaseToAdapty(reason: "didBecomeActive")

        // ATT ASA - only if not started yet
        guard !hasRequestedATT else { return }
        hasRequestedATT = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkTrackingAuthorization()
        }
    }

    // MARK: - ATT Flow

    private func checkTrackingAuthorization() {
        switch ATTrackingManager.trackingAuthorizationStatus {
        case .notDetermined:
            requestATTPermission()
        default:
            // There is already an answer - we update Adapty and start ASA
            handleTrackingStatus(ATTrackingManager.trackingAuthorizationStatus)
        }
    }

    private func requestATTPermission() {
        ATTrackingManager.requestTrackingAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.handleTrackingStatus(status)
            }
        }
    }

    /// Single point of processing ATT status - updates Adapty Firebase starts ASA
    private func handleTrackingStatus(_ status: ATTrackingManager.AuthorizationStatus) {
        let label = status.analyticsLabel

        print("[ATT] Status: \(label)")
        Analytics.logEvent("att_status", parameters: ["status": label as NSObject])

        // 1. ATT status → Adapty profile
        sendATTStatusToAdapty(status)

        // 2. IDFA → Adapty
        if status == .authorized {
            sendIDFAToAdapty()
        }

        // 3. ASA attribution
        fetchASAAttributionOnce()
    }

    // MARK: - AdSupport (IDFA) → Adapty

    private func sendIDFAToAdapty() {
        let zeroUUID = "00000000-0000-0000-0000-000000000000"
        let idfa = ASIdentifierManager.shared().advertisingIdentifier.uuidString

        guard idfa != zeroUUID else {
            print("[IDFA] IDFA is zeroed out, skipping")
            return
        }

        // IDFA передається через AdaptyProfile parameters
        Task {
            do {
                let builder = AdaptyProfileParameters.Builder()
                builder.with(appTrackingTransparencyStatus: ATTrackingManager.trackingAuthorizationStatus)

                try await Adapty.updateProfile(params: builder.build())
                print("[Adapty] IDFA profile updated. IDFA: \(idfa)")
            } catch {
                print("[Adapty] Error updating IDFA: \(error)")
            }
        }
    }

    // MARK: - ATT Status → Adapty Profile

    private func sendATTStatusToAdapty(_ status: ATTrackingManager.AuthorizationStatus) {
        Task {
            do {
                let builder = AdaptyProfileParameters.Builder()
                builder.with(appTrackingTransparencyStatus: status)
                try await Adapty.updateProfile(params: builder.build())
                print("[Adapty] ATT status updated: \(status.analyticsLabel)")
            } catch {
                print("[Adapty] Error updating ATT status: \(error)")
            }
        }
    }

    // MARK: - Apple Search Ads Attribution (once per session)

    private func fetchASAAttributionOnce() {
        guard !hasRunASAAttribution else { return }
        hasRunASAAttribution = true
        fetchASAAttribution()
    }

    private func fetchASAAttribution() {
        guard #available(iOS 14.3, *) else { return }

        DispatchQueue.global(qos: .background).async { [weak self] in
            do {
                let token = try AAAttribution.attributionToken()
                self?.resolveASAToken(token)
            } catch {
                print("[ASA] Token error: \(error.localizedDescription)")
                Analytics.logEvent("asa_token_error", parameters: [
                    "error": error.localizedDescription as NSObject
                ])
            }
        }
    }

    private func resolveASAToken(_ token: String) {
        guard let url = URL(string: "https://api-adservices.apple.com/api/v1/") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = token.data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            if let error = error {
                print("[ASA] Request failed: \(error.localizedDescription)")
                return
            }

            guard
                let data = data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                print("[ASA] Failed to parse response")
                return
            }

            self?.handleASAAttribution(json)
        }.resume()
    }

    private func handleASAAttribution(_ attribution: [String: Any]) {
        logASAToFirebase(attribution)
        sendASAToAdapty(attribution)
    }

    private func logASAToFirebase(_ attribution: [String: Any]) {
        let isAttributed = attribution["attribution"] as? Bool ?? false

        guard isAttributed else {
            Analytics.logEvent("user_acquisition", parameters: ["source": "organic" as NSObject])
            Analytics.setUserProperty("organic", forName: "acquisition_source")
            print("[ASA] User is organic")
            return
        }

        let campaignId    = attribution["campaignId"]     as? Int    ?? 0
        let adGroupId     = attribution["adGroupId"]      as? Int    ?? 0
        let keywordId     = attribution["keywordId"]      as? Int    ?? 0
        let conversionType = attribution["conversionType"] as? String ?? "unknown"
        let country       = attribution["countryOrRegion"] as? String ?? "unknown"
        let clickDate     = attribution["clickDate"]      as? String ?? "unknown"

        Analytics.logEvent("user_acquisition", parameters: [
            "source":           "apple_search_ads"  as NSObject,
            "campaign_id":      "\(campaignId)"     as NSObject,
            "adgroup_id":       "\(adGroupId)"      as NSObject,
            "keyword_id":       "\(keywordId)"      as NSObject,
            "conversion_type":  conversionType      as NSObject,
            "country":          country             as NSObject,
            "click_date":       clickDate           as NSObject
        ])

        Analytics.setUserProperty("apple_search_ads",  forName: "acquisition_source")
        Analytics.setUserProperty("\(campaignId)",     forName: "asa_campaign_id")
        Analytics.setUserProperty("\(adGroupId)",      forName: "asa_adgroup_id")
        Analytics.setUserProperty("\(keywordId)",      forName: "asa_keyword_id")
        Analytics.setUserProperty(country,             forName: "asa_country")

        print("[ASA] Attributed: campaign=\(campaignId), country=\(country)")
    }

    private func sendASAToAdapty(_ attribution: [String: Any]) {
        // Adapty 3.x — async/await
        Task {
            do {
                try await Adapty.updateAttribution(attribution, source: "apple_search_ads")
                print("[Adapty] ASA attribution sent")
            } catch {
                print("[Adapty] ASA attribution error: \(error)")
            }
        }
    }

    // MARK: - Navigation Bar Appearance

    private func setupNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.buttonAppearance.normal.titleTextAttributes     = [.foregroundColor: UIColor.systemRed]
        appearance.doneButtonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.systemRed]
        appearance.backButtonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.systemRed]

        let navBar = UINavigationBar.appearance()
        navBar.standardAppearance   = appearance
        navBar.scrollEdgeAppearance = appearance
        navBar.compactAppearance    = appearance
        navBar.tintColor = AppColors.primary
        UIToolbar.appearance().tintColor = AppColors.primary
    }

    // MARK: - UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {}

    func applicationWillTerminate(_ application: UIApplication) {
        CoreDataStack.shared.saveIfNeeded()
    }
}

// MARK: - Adapty Delegate

extension AppDelegate: AdaptyDelegate {

    func didLoadLatestProfile(_ profile: AdaptyProfile) {
        let isPremium = profile.accessLevels["premium"]?.isActive == true
        print("[Adapty] Profile loaded. Premium: \(isPremium ? "Yes" : "No")")

        DispatchQueue.main.async {
            SubscriptionManager.shared.checkPremiumStatus()
        }
    }

    func shouldAddStorePayment(for product: AdaptyDeferredProduct) -> Bool {
        return true
    }
}

// MARK: - ATT Status Label Helper

private extension ATTrackingManager.AuthorizationStatus {
    var analyticsLabel: String {
        switch self {
        case .authorized:    return "authorized"
        case .denied:        return "denied"
        case .restricted:    return "restricted"
        case .notDetermined: return "not_determined"
        @unknown default:    return "unknown"
        }
    }
}
