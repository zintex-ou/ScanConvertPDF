//
//  SettingsViewController.swift
//  ScanConvertPDF
//
//  Created by Developer
//

import UIKit
import MessageUI
import StoreKit

final class SettingsViewController: UIViewController {

    // MARK: - Settings Data

    private struct SettingsItem {
        let title: String
        let icon: String
        let action: (() -> Void)?
    }
    
    private struct SettingsSwitchItem {
        let title: String
        let icon: String
        let isOn: Bool
        let onChange: ((Bool) -> Void)?
    }

    private enum SettingsRow {
        case appInfo
        case item(SettingsItem)
        case switchItem(SettingsSwitchItem)
    }

    private struct SettingsSection {
        let title: String?
        let rows: [SettingsRow]
    }

    private var sections: [SettingsSection] = []
    
    private let appStoreID: String = "6748354307"
    
    private enum SupportEmail {
        static let address = "bhalatpuneey@gmail.com"
        static let subject = "PDF Scan & Convert Pro"
    }

    // MARK: - UI Elements

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        tv.dataSource = self
        tv.backgroundColor = AppColors.background
        tv.separatorStyle = .none
        tv.contentInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)

        tv.register(SettingsCell.self, forCellReuseIdentifier: SettingsCell.identifier)
        tv.register(SettingsSwitchCell.self, forCellReuseIdentifier: SettingsSwitchCell.identifier)
        tv.register(SettingsHeaderCell.self, forCellReuseIdentifier: SettingsHeaderCell.identifier)

        return tv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSections()
        setupUI()
        setupNavigationBar()
    }

    // MARK: - Setup

    private func setupSections() {
        let premiumItem = SettingsItem(title: "Premium Subscription", icon: "crown", action: { [weak self] in
            self?.openPremiumSubscription()
        })
        
        let darkModeSwitch = SettingsSwitchItem(
            title: "Dark Mode",
            icon: "moon.fill",
            isOn: isDarkModeEnabled(),
            onChange: { [weak self] isOn in
                self?.toggleDarkMode(isOn)
            }
        )

        let otherItems: [SettingsItem] = [
            SettingsItem(title: "Rate App", icon: "star", action: { [weak self] in
                self?.rateApp()
            }),
            SettingsItem(title: "Send Feedback", icon: "envelope", action: { [weak self] in
                self?.sendFeedback()
            }),
            SettingsItem(title: "Share App", icon: "square.and.arrow.up", action: { [weak self] in
                self?.shareApp()
            }),
            SettingsItem(title: "Tutorial", icon: "play.circle", action: { [weak self] in
                self?.openTutorial()
            }),
            SettingsItem(title: "Privacy Policy", icon: "doc.text", action: { [weak self] in
                self?.openPrivacyPolicy()
            }),
            SettingsItem(title: "Terms of Service", icon: "doc.text", action: { [weak self] in
                self?.openTermsOfService()
            })
        ]

        sections = [
            SettingsSection(title: nil, rows: [.item(premiumItem)]),
            SettingsSection(title: nil, rows: [.switchItem(darkModeSwitch)])
        ]
        
        sections.append(contentsOf: otherItems.map { SettingsSection(title: nil, rows: [.item($0)]) })
        sections.append(SettingsSection(title: nil, rows: [.appInfo]))
    }

    private func setupUI() {
        view.backgroundColor = AppColors.background
        view.addSubview(tableView)

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupNavigationBar() {
        title = "Settings"
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppColors.background
        appearance.titleTextAttributes = [
            .foregroundColor: AppColors.darkGray,
            .font: AppFonts.bold(24)
        ]

        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.isTranslucent = false
    }
    
    // MARK: - Dark Mode

    private func isDarkModeEnabled() -> Bool {
        return AppSettings.shared.isDarkModeEnabled
    }

    private func toggleDarkMode(_ isEnabled: Bool) {
        AppSettings.shared.isDarkModeEnabled = isEnabled
        applyDarkMode(isEnabled)
    }

    private func applyDarkMode(_ isEnabled: Bool) {
        let style: UIUserInterfaceStyle = isEnabled ? .dark : .light
        
        // Застосувати до всіх вікон
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { window in
                window.overrideUserInterfaceStyle = style
            }
    }

    // MARK: - Actions

    private func rateApp() {
        let urlString = "itms-apps://apps.apple.com/app/id\(appStoreID)?action=write-review"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            return
        }

        showAlert(title: "Rate App", message: "Unable to open the App Store right now.")
    }

    private func sendFeedback() {
        let body = makeSupportEmailBody()

        // 1) In-app mail composer
        if MFMailComposeViewController.canSendMail() {
            let mailVC = MFMailComposeViewController()
            mailVC.mailComposeDelegate = self
            mailVC.setToRecipients([SupportEmail.address])
            mailVC.setSubject(SupportEmail.subject)
            mailVC.setMessageBody(body, isHTML: false)
            present(mailVC, animated: true)
            return
        }

        // 2) mailto fallback
        guard let url = makeMailtoURL(to: SupportEmail.address, subject: SupportEmail.subject, body: body),
              UIApplication.shared.canOpenURL(url) else {
            showAlert(title: "Email Not Available",
                      message: "No mail app is available on this device.")
            return
        }

        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            guard let self else { return }
            if !success {
                self.showAlert(title: "Email Not Available",
                               message: "Unable to open a mail app on this device.")
            }
        }
    }

    private func makeMailtoURL(to: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }

    private func makeSupportEmailBody() -> String {
        """
        Describe your issue here:

        ---
        \(appAndBuildString())
        \(deviceSummaryString())
        """
    }

    private func appAndBuildString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "App version: \(version), Build: \(build)"
    }

    private func deviceSummaryString() -> String {
        let osName = UIDevice.current.systemName
        let osVersion = UIDevice.current.systemVersion
        let modelIdentifier = hardwareModelIdentifier() ?? "UnknownModel"
        return "\(osName) \(osVersion), \(modelIdentifier)"
    }

    private func hardwareModelIdentifier() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(validatingUTF8: ptr)
            }
        }
    }

    private func openPrivacyPolicy() {
        if let url = URL(string: "https://telegra.ph/Privacy-Policy--PDF-Scan--Convert-Pro-01-27") {
            UIApplication.shared.open(url)
        }
    }

    private func openTermsOfService() {
        if let url = URL(string: "https://telegra.ph/Terms-of-Use--PDF-Scan--Convert-Pro-01-27") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openPremiumSubscription(
        placementID: String = AppConfig.Adapty.paywallMainPlacementID
    ) {
        view.isUserInteractionEnabled = false

        Task { @MainActor in
            await SubscriptionManager.shared.updatePremiumStatus()

            // Якщо вже Premium — можна просто показати повідомлення (або нічого не робити)
            if SubscriptionManager.shared.isPremiumActive {
                self.view.isUserInteractionEnabled = true
                self.showAlert(title: "Premium", message: "Your Premium subscription is active.")
                return
            }

            // важливо: якщо вже щось показано — не лочимо UI назавжди
            guard self.presentedViewController == nil else {
                self.view.isUserInteractionEnabled = true
                return
            }

            SubscriptionManager.shared.presentPaywallWithFallback(
                placementID: placementID,
                from: self,
                animated: true
            ) { [weak self] result in
                guard let self else { return }
                self.view.isUserInteractionEnabled = true

                switch result {
                case .purchased, .restored:
                    Task { @MainActor in
                        await SubscriptionManager.shared.updatePremiumStatus()
                        if SubscriptionManager.shared.isPremiumActive {
                            self.showAlert(title: "Success", message: "Premium unlocked")
                        }
                    }
                case .dismissed, .skipped, .loadingError, .purchaseError:
                    break
                }
            }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }
    
    private func shareApp() {
        let shareText = "PDF Scan & Convert Pro — scan and convert to PDF."
        guard let appURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)") else { return }

        let activityVC = UIActivityViewController(activityItems: [shareText, appURL], applicationActivities: nil)

        if UIDevice.current.userInterfaceIdiom == .pad,
           let pop = activityVC.popoverPresentationController {
            pop.sourceView = self.view
            pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }

        present(activityVC, animated: true)
    }

    private func openTutorial() {
        let vc = DefaultOnboardingViewController(showCloseButton: true)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension SettingsViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = sections[indexPath.section].rows[indexPath.row]

        switch row {
        case .appInfo:
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsHeaderCell.identifier,
                for: indexPath
            ) as! SettingsHeaderCell

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            cell.configure(title: "PDF Scan & Convert Pro", version: "Version \(version)", iconImageName: "mini-app-icon")
            cell.selectionStyle = .none
            return cell

        case .item(let item):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsCell.identifier,
                for: indexPath
            ) as! SettingsCell
            cell.configure(with: item.title, icon: item.icon, iconColor: AppColors.primary)
            return cell
            
        case .switchItem(let switchItem):
            let cell = tableView.dequeueReusableCell(
                withIdentifier: SettingsSwitchCell.identifier,
                for: indexPath
            ) as! SettingsSwitchCell
            cell.configure(
                with: switchItem.title,
                icon: switchItem.icon,
                iconColor: AppColors.primary,
                isOn: switchItem.isOn,
                onChange: switchItem.onChange
            )
            cell.selectionStyle = .none
            return cell
        }
    }
}

// MARK: - UITableViewDelegate

extension SettingsViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let row = sections[indexPath.section].rows[indexPath.row]
        switch row {
        case .appInfo, .switchItem:
            return
        case .item(let item):
            item.action?()
        }
    }

    // Висота як у DocumentCollectionCell
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let row = sections[indexPath.section].rows[indexPath.row]
        switch row {
        case .item, .switchItem: return 80
        case .appInfo: return 180
        }
    }

    // Прибрати "пустий" header
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        sections[section].title == nil ? .leastNormalMagnitude : UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        sections[section].title == nil ? UIView(frame: .zero) : nil
    }

    // Spacing між "картками" (секціями)
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        section == sections.count - 1 ? .leastNormalMagnitude : 12
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView(frame: .zero)
    }
}

// MARK: - MFMailComposeViewControllerDelegate

extension SettingsViewController: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true)
    }
}

// MARK: - SettingsSwitchCell

final class SettingsSwitchCell: UITableViewCell {
    
    static let identifier = "SettingsSwitchCell"
    
    private var onChangeHandler: ((Bool) -> Void)?
    
    // MARK: - Card
    
    private let cardView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = AppColors.cellBackground
        v.layer.cornerRadius = 18
        v.layer.cornerCurve = .continuous
        
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOffset = CGSize(width: 0, height: 1)
        v.layer.shadowRadius = 1
        v.layer.shadowOpacity = 0.10
        return v
    }()
    
    // MARK: - UI
    
    private lazy var iconContainerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.layer.cornerRadius = 16
        v.layer.cornerCurve = .continuous
        v.layer.masksToBounds = true
        v.layer.borderWidth = 1
        return v
    }()
    
    private lazy var iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        return iv
    }()
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppFonts.regular(16)
        label.textColor = AppColors.textPrimary
        return label
    }()
    
    private let toggleSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.onTintColor = AppColors.primary
        return toggle
    }()
    
    private let symbolConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular, scale: .medium)
    
    // MARK: - Init
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        selectionStyle = .none
        accessoryType = .none
        
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        
        // IMPORTANT: do not clip shadow
        clipsToBounds = false
        contentView.clipsToBounds = false
        layer.masksToBounds = false
        contentView.layer.masksToBounds = false
        
        contentView.addSubview(cardView)
        
        cardView.addSubview(iconContainerView)
        iconContainerView.addSubview(iconImageView)
        cardView.addSubview(titleLabel)
        cardView.addSubview(toggleSwitch)
        
        toggleSwitch.addTarget(self, action: #selector(switchValueChanged), for: .valueChanged)
        
        NSLayoutConstraint.activate([
            // tiny vertical inset to give space for shadow (like collection interGroupSpacing)
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 2),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            
            // keep horizontal as-is (insetGrouped controls side insets)
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            
            iconContainerView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            iconContainerView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconContainerView.widthAnchor.constraint(equalToConstant: 56),
            iconContainerView.heightAnchor.constraint(equalToConstant: 56),
            
            iconImageView.centerXAnchor.constraint(equalTo: iconContainerView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),
            
            toggleSwitch.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            toggleSwitch.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: toggleSwitch.leadingAnchor, constant: -12)
        ])
    }
    
    // MARK: - Configure
    
    @objc private func switchValueChanged() {
        onChangeHandler?(toggleSwitch.isOn)
    }
    
    func configure(with title: String, icon: String, iconColor: UIColor, isOn: Bool, onChange: ((Bool) -> Void)?) {
        titleLabel.text = title
        
        iconImageView.image = UIImage(systemName: icon, withConfiguration: symbolConfig)
        iconImageView.tintColor = iconColor
        
        iconContainerView.backgroundColor = iconColor.withAlphaComponent(0.14)
        iconContainerView.layer.borderColor = iconColor.withAlphaComponent(0.28).cgColor
        
        toggleSwitch.isOn = isOn
        onChangeHandler = onChange
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        iconImageView.image = nil
        iconImageView.tintColor = nil
        iconContainerView.backgroundColor = nil
        iconContainerView.layer.borderColor = nil
        toggleSwitch.isOn = false
        onChangeHandler = nil
    }
}
// MARK: - SettingsHeaderCell (без cardView)

final class SettingsHeaderCell: UITableViewCell {

    static let identifier = "SettingsHeaderCell"

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 16
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = AppFonts.bold(22)
        l.textColor = AppColors.textPrimary
        l.textAlignment = .center
        return l
    }()

    private let versionLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = AppFonts.regular(14)
        l.textColor = AppColors.textSecondary
        l.textAlignment = .center
        return l
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .none
        accessoryType = .none

        // Робимо сам contentView "карткою"
        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 12
        contentView.layer.masksToBounds = true

        contentView.addSubview(iconImageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(versionLabel)

        // Важливо: щоб insetGrouped не "з'їдав" відступи — робимо margins = 16
        contentView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        contentView.preservesSuperviewLayoutMargins = false

        NSLayoutConstraint.activate([
            iconImageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            iconImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 70),
            iconImageView.heightAnchor.constraint(equalToConstant: 70),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 12),
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            versionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            versionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    func configure(title: String, version: String, iconImageName: String) {
        titleLabel.text = title
        versionLabel.text = version
        iconImageView.image = UIImage(named: iconImageName)
    }
}

