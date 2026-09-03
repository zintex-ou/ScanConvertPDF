//
//  RemoteConfigManager.swift
//  ScanConvertPDF
//
//  Created on 02.03.2026.
//

import Foundation
import FirebaseRemoteConfig

final class RemoteConfigManager {

    static let shared = RemoteConfigManager()
    private let remoteConfig = RemoteConfig.remoteConfig()
    
    // Bootstrap status
    private(set) var isBootstrapped = false
    
    // MARK: - Keys
    
    private enum Key {
        static let showPaywallOnLaunch = "show_paywall_on_launch"
    }
    
    // MARK: - Default Values
    
    private enum DefaultValue {
        static let showPaywallOnLaunch = false
        static let minimumFetchInterval: TimeInterval = 0
    }

    private init() {
        setupRemoteConfig()
        setDefaultValues()
    }
    
    private func setupRemoteConfig() {
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = DefaultValue.minimumFetchInterval
        remoteConfig.configSettings = settings
    }
    
    private func setDefaultValues() {
        remoteConfig.setDefaults([
            Key.showPaywallOnLaunch: NSNumber(value: DefaultValue.showPaywallOnLaunch)
        ])
    }

    // MARK: - Bootstrap
    
    /// Call once after FirebaseApp.configure()
    /// Fetches Remote Config from Firebase
    @discardableResult
    func bootstrap() async -> Bool {
        guard !isBootstrapped else {
            print("[RemoteConfig] Already bootstrapped")
            return true
        }
        
        do {
            let status = try await remoteConfig.fetchAndActivate()
            
            switch status {
            case .successFetchedFromRemote:
                print("[RemoteConfig] Successfully fetched from remote")
                isBootstrapped = true
                logAllValues()
                return true
                
            case .successUsingPreFetchedData:
                print("[RemoteConfig] Using pre-fetched data")
                isBootstrapped = true
                logAllValues()
                return true
                
            case .error:
                print("[RemoteConfig] Fetch returned error status")
                isBootstrapped = false
                return false
                
            @unknown default:
                print("[RemoteConfig] Unknown fetch status")
                isBootstrapped = false
                return false
            }
        } catch {
            print("[RemoteConfig] Error: \(error.localizedDescription)")
            isBootstrapped = false
            return false
        }
    }
    
    /// Refreshes Remote Config (can be called periodically)
    @discardableResult
    func refresh() async -> Bool {
        do {
            let status = try await remoteConfig.fetchAndActivate()
            let success = status == .successFetchedFromRemote || status == .successUsingPreFetchedData
            
            if success {
                print("[RemoteConfig] Refreshed successfully")
                logAllValues()
            }
            
            return success
        } catch {
            print("[RemoteConfig] Refresh error: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - Logging
    
    private func logAllValues() {
        print("[RemoteConfig] Current values:")
        print("  • showPaywallOnLaunch: \(showPaywallOnLaunch)")
    }

    // MARK: - Public Access
    
    /// Whether to show paywall on launch
    var showPaywallOnLaunch: Bool {
        remoteConfig[Key.showPaywallOnLaunch].boolValue
    }
}
