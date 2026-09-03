//
//  StoreKitPaywallViewController.swift
//  ScanConvertPDF
//
//  Created by Developer on 22.01.2026.
//

import UIKit
import StoreKit

// MARK: - Recommended: centralized product ids

struct ProductPair {
    let trial: String
    let regular: String

    func id(isTrialEnabled: Bool) -> String {
        isTrialEnabled ? trial : regular
    }

    var all: [String] { [trial, regular] }
}

enum PaywallProducts {
    enum Plan {
        case weekly
        case monthly
        case yearly

        var ids: ProductPair {
            switch self {
            case .weekly:
                return .init(
                    trial: "premium.weekly.trial",
                    regular: "premium.weekly"
                )
            case .monthly:
                return .init(
                    trial: "premium.monthly.trial",
                    regular: "premium.monthly"
                )
            case .yearly:
                return .init(
                    trial: "premium.yearly.trial",
                    regular: "premium.yearly"
                )
            }
        }
    }

    static let allProductIds: [String] = [
        Plan.weekly.ids.all,
        Plan.monthly.ids.all,
        Plan.yearly.ids.all
    ].flatMap { $0 }
}

extension SubscriptionButton.SubscriptionType {
    var plan: PaywallProducts.Plan {
        switch self {
        case .weekly:  return .weekly
        case .monthly: return .monthly
        case .yearly:  return .yearly
        }
    }
}

// MARK: - Paywall VC

final class StoreKitPaywallViewController: UIViewController {

    // MARK: - Navigation Callback

    var onClose: (() -> Void)?
    var onPurchaseSuccess: (() -> Void)?

    // MARK: - Properties

    private var products: [Product] = []
    private var selectedProductId: String?
    private var isTrialEnabled: Bool = true

    private var allProductIds: [String] {
        PaywallProducts.allProductIds
    }

    private var currentSubscriptionType: SubscriptionButton.SubscriptionType = .yearly

    // MARK: - UI Elements

    private lazy var closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark"), for: .normal)
        button.tintColor = AppColors.textSecondary
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var mainStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.distribution = .fill
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var headerImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(named: "paywall-header-image")
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = "Unlock all premium features"
        label.font = .systemFont(ofSize: 26, weight: .bold)
        label.textColor = AppColors.textPrimary
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Scan, convert, and export without limits"
        label.font = .systemFont(ofSize: 16)
        label.textColor = AppColors.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var subscriptionsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var yearlyButton: SubscriptionButton = {
        let button = SubscriptionButton(type: .yearly)
        button.addTarget(self, action: #selector(subscriptionButtonTapped(_:)), for: .touchUpInside)
        return button
    }()

    private lazy var monthlyButton: SubscriptionButton = {
        let button = SubscriptionButton(type: .monthly)
        button.addTarget(self, action: #selector(subscriptionButtonTapped(_:)), for: .touchUpInside)
        return button
    }()

    private lazy var weeklyButton: SubscriptionButton = {
        let button = SubscriptionButton(type: .weekly)
        button.addTarget(self, action: #selector(subscriptionButtonTapped(_:)), for: .touchUpInside)
        return button
    }()

    private lazy var trialContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var trialTitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Free trial"
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = AppColors.textPrimary
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var trialSubtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "Try premium features at no cost"
        label.font = .systemFont(ofSize: 14)
        label.textColor = AppColors.textSecondary
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var trialSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = true
        toggle.onTintColor = AppColors.primary
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.addTarget(self, action: #selector(trialSwitchChanged(_:)), for: .valueChanged)
        return toggle
    }()

    private lazy var continueButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Continue", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        button.setTitleColor(AppColors.menuAccent, for: .normal)
        button.backgroundColor = AppColors.primary
        button.layer.cornerRadius = 28
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(continueButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var bottomButtonsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var termsButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Terms of Use", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.setTitleColor(AppColors.textSecondary, for: .normal)
        button.addTarget(self, action: #selector(termsButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var privacyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Privacy Policy", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.setTitleColor(AppColors.textSecondary, for: .normal)
        button.addTarget(self, action: #selector(privacyButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var restoreButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Restore", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13)
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.setTitleColor(AppColors.textSecondary, for: .normal)
        button.addTarget(self, action: #selector(restoreButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = AppColors.primary
        indicator.hidesWhenStopped = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    // MARK: - Init

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()

        continueButton.isEnabled = false
        continueButton.alpha = 0.5

        selectDefaultPlan()
        loadProducts()
    }

    // MARK: - Setup UI

    private func setupUI() {
        view.backgroundColor = AppColors.background

        view.addSubview(closeButton)
        view.addSubview(mainStackView)
        view.addSubview(loadingIndicator)

        subscriptionsStackView.addArrangedSubview(yearlyButton)
        subscriptionsStackView.addArrangedSubview(monthlyButton)
        subscriptionsStackView.addArrangedSubview(weeklyButton)

        trialContainerView.addSubview(trialTitleLabel)
        trialContainerView.addSubview(trialSubtitleLabel)
        trialContainerView.addSubview(trialSwitch)

        bottomButtonsStackView.addArrangedSubview(termsButton)
        bottomButtonsStackView.addArrangedSubview(privacyButton)
        bottomButtonsStackView.addArrangedSubview(restoreButton)

        mainStackView.addArrangedSubview(headerImageView)
        mainStackView.addArrangedSubview(titleLabel)
        mainStackView.addArrangedSubview(subtitleLabel)
        mainStackView.addArrangedSubview(subscriptionsStackView)
        mainStackView.addArrangedSubview(trialContainerView)
        mainStackView.addArrangedSubview(continueButton)
        mainStackView.addArrangedSubview(bottomButtonsStackView)

        mainStackView.setCustomSpacing(24, after: headerImageView)
        mainStackView.setCustomSpacing(8, after: titleLabel)
        mainStackView.setCustomSpacing(24, after: subtitleLabel)
        mainStackView.setCustomSpacing(20, after: subscriptionsStackView)
        mainStackView.setCustomSpacing(24, after: trialContainerView)
        mainStackView.setCustomSpacing(20, after: continueButton)

        headerImageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        headerImageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        [
            titleLabel,
            subtitleLabel,
            subscriptionsStackView,
            trialContainerView,
            continueButton,
            bottomButtonsStackView
        ].forEach {
            $0.setContentHuggingPriority(.required, for: .vertical)
        }

        setupConstraints()
    }

    private func setupConstraints() {
        let imageHeightConstraint = headerImageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        imageHeightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            mainStackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 58),
            mainStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            mainStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            mainStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            headerImageView.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
            headerImageView.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),
            imageHeightConstraint,
            headerImageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),

            continueButton.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
            continueButton.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),
            continueButton.heightAnchor.constraint(equalToConstant: 56),

            subscriptionsStackView.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
            subscriptionsStackView.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),

            trialContainerView.leadingAnchor.constraint(equalTo: mainStackView.leadingAnchor),
            trialContainerView.trailingAnchor.constraint(equalTo: mainStackView.trailingAnchor),

            trialTitleLabel.topAnchor.constraint(equalTo: trialContainerView.topAnchor),
            trialTitleLabel.leadingAnchor.constraint(equalTo: trialContainerView.leadingAnchor),
            trialTitleLabel.trailingAnchor.constraint(equalTo: trialSwitch.leadingAnchor, constant: -12),

            trialSubtitleLabel.topAnchor.constraint(equalTo: trialTitleLabel.bottomAnchor, constant: 4),
            trialSubtitleLabel.leadingAnchor.constraint(equalTo: trialContainerView.leadingAnchor),
            trialSubtitleLabel.trailingAnchor.constraint(equalTo: trialSwitch.leadingAnchor, constant: -12),
            trialSubtitleLabel.bottomAnchor.constraint(equalTo: trialContainerView.bottomAnchor),

            trialSwitch.topAnchor.constraint(equalTo: trialContainerView.topAnchor),
            trialSwitch.trailingAnchor.constraint(equalTo: trialContainerView.trailingAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        [yearlyButton, monthlyButton, weeklyButton].forEach { button in
            button.heightAnchor.constraint(equalToConstant: 70).isActive = true
        }
    }

    // MARK: - Paywall selection helpers

    private func selectDefaultPlan() {
        currentSubscriptionType = .yearly

        yearlyButton.setSelected(true)
        monthlyButton.setSelected(false)
        weeklyButton.setSelected(false)

        updateSelectedProductId()
        refreshDisplayedPricesIfPossible()
    }

    private func updateSelectedProductId() {
        selectedProductId = currentSubscriptionType.plan.ids.id(isTrialEnabled: isTrialEnabled)
    }

    private func refreshDisplayedPricesIfPossible() {
        guard !products.isEmpty else { return }

        // Show price corresponding to current trial toggle
        if let weekly = products.first(where: { $0.id == PaywallProducts.Plan.weekly.ids.id(isTrialEnabled: isTrialEnabled) }) {
            weeklyButton.configure(title: "Weekly", price: weekly.displayPrice)
        }
        if let monthly = products.first(where: { $0.id == PaywallProducts.Plan.monthly.ids.id(isTrialEnabled: isTrialEnabled) }) {
            monthlyButton.configure(title: "Monthly", price: monthly.displayPrice)
        }
        if let yearly = products.first(where: { $0.id == PaywallProducts.Plan.yearly.ids.id(isTrialEnabled: isTrialEnabled) }) {
            yearlyButton.configure(title: "Yearly", price: yearly.displayPrice)
        }
    }

    // MARK: - StoreKit 2

    private func loadProducts() {
        loadingIndicator.startAnimating()
        Task {
            do {
                let storeProducts = try await Product.products(for: allProductIds)

                await MainActor.run {
                    self.products = storeProducts
                    self.loadingIndicator.stopAnimating()

                    self.refreshDisplayedPricesIfPossible()

                    if !storeProducts.isEmpty {
                        self.continueButton.isEnabled = true
                        self.continueButton.alpha = 1.0
                    }
                }
            } catch {
                await MainActor.run {
                    self.loadingIndicator.stopAnimating()
                    print("Failed to load products: \(error)")
                    self.showError("Failed to load products. Please try again.")
                }
            }
        }
    }

    private func purchase(productId: String) {
        guard let product = products.first(where: { $0.id == productId }) else {
            showError("Product not found")
            return
        }

        loadingIndicator.startAnimating()
        continueButton.isEnabled = false

        Task {
            do {
                let result = try await product.purchase()

                await MainActor.run {
                    self.loadingIndicator.stopAnimating()
                    self.continueButton.isEnabled = true

                    switch result {
                    case .success(let verification):
                        switch verification {
                        case .verified(let transaction):
                            print("Purchase successful: \(transaction.productID)")
                            Task { await transaction.finish() }
                            self.handleSuccessfulPurchase()

                        case .unverified(_, let error):
                            print("Unverified purchase: \(error)")
                            self.showError("Purchase verification failed")
                        }

                    case .userCancelled:
                        print("User cancelled")

                    case .pending:
                        print("Purchase pending")
                        self.showAlert(title: "Pending", message: "Your purchase is pending approval.")

                    @unknown default:
                        break
                    }
                }
            } catch {
                await MainActor.run {
                    self.loadingIndicator.stopAnimating()
                    self.continueButton.isEnabled = true
                    self.showError("Purchase failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func restorePurchases() {
        loadingIndicator.startAnimating()

        Task {
            do {
                try await AppStore.sync()

                var hasActiveSubscription = false

                for await result in Transaction.currentEntitlements {
                    if case .verified(let transaction) = result {
                        if transaction.productType == .autoRenewable {
                            hasActiveSubscription = true
                            break
                        }
                    }
                }

                await MainActor.run {
                    self.loadingIndicator.stopAnimating()

                    if hasActiveSubscription {
                        self.showAlert(title: "Success", message: "Your subscription has been restored.") {
                            self.handleSuccessfulPurchase()
                        }
                    } else {
                        self.showAlert(title: "No Subscription", message: "No active subscription found.")
                    }
                }
            } catch {
                await MainActor.run {
                    self.loadingIndicator.stopAnimating()
                    self.showError("Restore failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleSuccessfulPurchase() {
        onPurchaseSuccess?()
        onClose?()
    }

    // MARK: - Actions

    @objc private func closeButtonTapped() {
        onClose?()
    }

    @objc private func subscriptionButtonTapped(_ sender: SubscriptionButton) {
        yearlyButton.setSelected(false)
        monthlyButton.setSelected(false)
        weeklyButton.setSelected(false)

        sender.setSelected(true)
        currentSubscriptionType = sender.subscriptionType

        updateSelectedProductId()
    }

    @objc private func trialSwitchChanged(_ sender: UISwitch) {
        isTrialEnabled = sender.isOn

        UIView.animate(withDuration: 0.3) {
            self.trialTitleLabel.alpha = sender.isOn ? 1.0 : 0.5
            self.trialSubtitleLabel.alpha = sender.isOn ? 1.0 : 0.5
        }

        updateSelectedProductId()
        refreshDisplayedPricesIfPossible()
    }

    @objc private func continueButtonTapped() {
        guard let productId = selectedProductId else {
            showError("Please select a subscription plan")
            return
        }

        purchase(productId: productId)
    }

    @objc private func termsButtonTapped() {
        openURL("https://telegra.ph/Terms-of-Use--PDF-Scan--Convert-Pro-01-27")
    }

    @objc private func privacyButtonTapped() {
        openURL("https://telegra.ph/Privacy-Policy--PDF-Scan--Convert-Pro-01-27")
    }

    @objc private func restoreButtonTapped() {
        restorePurchases()
    }

    // MARK: - Helpers

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    private func showError(_ message: String) {
        showAlert(title: "Error", message: message)
    }

    private func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }
}

// MARK: - SubscriptionButton

final class SubscriptionButton: UIControl {

    enum SubscriptionType {
        case weekly
        case monthly
        case yearly
    }

    let subscriptionType: SubscriptionType
    private var isSelectedState: Bool = false

    private lazy var containerView: UIView = {
        let view = UIView()
        view.backgroundColor = AppColors.cellBackground
        view.layer.cornerRadius = 16
        view.layer.borderWidth = 2
        view.layer.borderColor = UIColor.clear.cgColor
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = AppColors.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var priceLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = AppColors.primary
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var detailLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 13)
        label.textColor = AppColors.textSecondary
        label.textAlignment = .right
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var savingsBadge: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = AppColors.background
        label.backgroundColor = AppColors.primary
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var popularBadge: PaddedLabel = {
        let label = PaddedLabel()
        label.text = "MOST POPULAR"
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = AppColors.background
        label.backgroundColor = AppColors.primary
        label.textAlignment = .center
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var checkmarkImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.image = UIImage(systemName: "checkmark.circle.fill")
        imageView.tintColor = AppColors.primary
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    // MARK: - Init

    init(type: SubscriptionType) {
        self.subscriptionType = type
        super.init(frame: .zero)
        setupUI()

        if type == .yearly {
            popularBadge.isHidden = false
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(containerView)
        containerView.addSubview(titleLabel)
        containerView.addSubview(priceLabel)
        containerView.addSubview(detailLabel)
        containerView.addSubview(savingsBadge)
        containerView.addSubview(checkmarkImageView)
        addSubview(popularBadge)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),

            priceLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            priceLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            priceLabel.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -14),

            checkmarkImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            checkmarkImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            checkmarkImageView.widthAnchor.constraint(equalToConstant: 24),
            checkmarkImageView.heightAnchor.constraint(equalToConstant: 24),

            detailLabel.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: checkmarkImageView.leadingAnchor, constant: -12),
            detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: priceLabel.trailingAnchor, constant: 16),

            savingsBadge.bottomAnchor.constraint(equalTo: detailLabel.topAnchor, constant: -4),
            savingsBadge.trailingAnchor.constraint(equalTo: detailLabel.trailingAnchor),
            savingsBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            savingsBadge.heightAnchor.constraint(equalToConstant: 18),

            popularBadge.centerYAnchor.constraint(equalTo: topAnchor),
            popularBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            popularBadge.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    // MARK: - Configuration

    func configure(title: String, price: String) {
        titleLabel.text = title
        priceLabel.text = price
    }

    func configure(title: String, price: String, detail: String?, savings: String? = nil) {
        titleLabel.text = title
        priceLabel.text = price
        detailLabel.text = detail

        if let savings = savings {
            savingsBadge.text = " \(savings) "
            savingsBadge.isHidden = false
        } else {
            savingsBadge.isHidden = true
        }
    }

    func setSelected(_ selected: Bool) {
        isSelectedState = selected

        UIView.animate(withDuration: 0.2) {
            if selected {
                self.containerView.backgroundColor = AppColors.primary.withAlphaComponent(0.15)
                self.containerView.layer.borderColor = AppColors.primary.cgColor
                self.titleLabel.textColor = AppColors.textPrimary
                self.priceLabel.textColor = AppColors.primary
                self.detailLabel.textColor = AppColors.textPrimary.withAlphaComponent(0.8)
                self.checkmarkImageView.isHidden = false
            } else {
                self.containerView.backgroundColor = AppColors.cellBackground
                self.containerView.layer.borderColor = UIColor.clear.cgColor
                self.titleLabel.textColor = AppColors.textPrimary
                self.priceLabel.textColor = AppColors.primary
                self.detailLabel.textColor = AppColors.textSecondary
                self.checkmarkImageView.isHidden = true
            }
        }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        UIView.animate(withDuration: 0.1) {
            self.transform = CGAffineTransform(scaleX: 0.98, y: 0.98)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.1) {
            self.transform = .identity
        }
        sendActions(for: .touchUpInside)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.1) {
            self.transform = .identity
        }
    }
}

final class PaddedLabel: UILabel {
    var textInsets = UIEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: textInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + textInsets.left + textInsets.right,
            height: size.height + textInsets.top + textInsets.bottom
        )
    }
}
