//
//  RateAppViewController.swift
//  ScanConvertPDF
//
//  Created by Developer on 22.01.2026.
//


import UIKit
import StoreKit

final class RateAppViewController: UIViewController {

    // MARK: - Public
    typealias SubmitHandler = (Int) -> Void
    typealias DismissHandler = () -> Void

    init(
        initialRating: Int = 5,
        onSubmit: SubmitHandler? = nil,
        onDismiss: DismissHandler? = nil
    ) {
        self.initialRating = Self.clampRating(initialRating, max: 5)
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss

        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Private
    private enum Strings {
        static let title = "Rate the app"
        static let message = "Enjoying the app? Your rating helps us improve."
        static let thanks = "Thanks for your feedback!"
        static let notNow = "Not now"
        static let submit = "Submit"
    }

    private static func clampRating(_ value: Int, max: Int) -> Int {
        Swift.max(1, Swift.min(max, value))
    }

    private let initialRating: Int
    private let onSubmit: SubmitHandler?
    private let onDismiss: DismissHandler?

    // MARK: - UI
    private let dimView = UIView()
    private let alertView = UIView()

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let thanksLabel = UILabel()

    private let cancelButton = UIButton(type: .system)
    private let submitButton = UIButton(type: .system)

    private lazy var starsView: StarRatingView = {
        let v = StarRatingView(stars: 5, initial: initialRating)
        v.onChange = { _ in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        return v
    }()

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        layoutUI()
        animateIn()
    }

    // MARK: - UI
    private func buildUI() {
        view.backgroundColor = .clear

        // Simple dim background
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimView.alpha = 0
        dimView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimView)

        // Alert card
        alertView.backgroundColor = AppColors.cellBackground
        alertView.layer.cornerRadius = 20
        alertView.layer.masksToBounds = false

        // Border
        // alertView.layer.borderWidth = 1
        // alertView.layer.borderColor = AppColors.primary.withAlphaComponent(0.2).cgColor

        // Shadow
        alertView.layer.shadowColor = UIColor.black.cgColor
        alertView.layer.shadowOpacity = 0.4
        alertView.layer.shadowRadius = 20
        alertView.layer.shadowOffset = CGSize(width: 0, height: 10)
        view.addSubview(alertView)

        // Title
        titleLabel.text = Strings.title
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        titleLabel.font = AppFonts.bold(20)
        titleLabel.textColor = AppColors.textPrimary

        // Message
        messageLabel.text = Strings.message
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.textColor = AppColors.textSecondary
        messageLabel.font = AppFonts.medium(16)

        // Thanks
        thanksLabel.text = Strings.thanks
        thanksLabel.textAlignment = .center
        thanksLabel.textColor = AppColors.textPrimary
        thanksLabel.font = AppFonts.semibold(16)
        thanksLabel.alpha = 0

        // Cancel
        cancelButton.setTitle(Strings.notNow, for: .normal)
        cancelButton.titleLabel?.font = AppFonts.semibold(15)
        cancelButton.setTitleColor(AppColors.textSecondary, for: .normal)
        cancelButton.layer.cornerRadius = 12
        cancelButton.layer.borderWidth = 1.5
        cancelButton.layer.borderColor = AppColors.textSecondary.withAlphaComponent(0.25).cgColor
        cancelButton.backgroundColor = .clear
        cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)

        // Submit
        submitButton.setTitle(Strings.submit, for: .normal)
        submitButton.titleLabel?.font = AppFonts.bold(15)
        submitButton.setTitleColor(.white, for: .normal)
        submitButton.backgroundColor = AppColors.primary
        submitButton.layer.cornerRadius = 12

        // Glow
        submitButton.layer.shadowPath = nil
        submitButton.layer.masksToBounds = true
        submitButton.layer.shadowOpacity = 0

        submitButton.addTarget(self, action: #selector(submitPressed), for: .touchUpInside)

        [titleLabel, messageLabel, starsView, thanksLabel, cancelButton, submitButton].forEach { alertView.addSubview($0) }

        // Tap outside to dismiss
        let tap = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        view.addGestureRecognizer(tap)
    }

    private func layoutUI() {
        alertView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        starsView.translatesAutoresizingMaskIntoConstraints = false
        thanksLabel.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        submitButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            // dimView
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if UIDevice.current.userInterfaceIdiom == .pad {
            let widthConstraint = alertView.widthAnchor.constraint(equalToConstant: 380)
            widthConstraint.priority = .defaultHigh

            NSLayoutConstraint.activate([
                alertView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                alertView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                widthConstraint,
                alertView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
                alertView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24)
            ])
        } else {
            NSLayoutConstraint.activate([
                alertView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                alertView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                alertView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
                alertView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
            ])
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: alertView.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: alertView.trailingAnchor, constant: -24),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: alertView.trailingAnchor, constant: -24),

            starsView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 24),
            starsView.centerXAnchor.constraint(equalTo: alertView.centerXAnchor),
            starsView.heightAnchor.constraint(equalToConstant: 44),

            thanksLabel.topAnchor.constraint(equalTo: starsView.bottomAnchor, constant: 12),
            thanksLabel.centerXAnchor.constraint(equalTo: alertView.centerXAnchor),

            cancelButton.topAnchor.constraint(equalTo: thanksLabel.bottomAnchor, constant: 20),
            cancelButton.leadingAnchor.constraint(equalTo: alertView.leadingAnchor, constant: 20),
            cancelButton.heightAnchor.constraint(equalToConstant: 48),

            submitButton.topAnchor.constraint(equalTo: thanksLabel.bottomAnchor, constant: 20),
            submitButton.trailingAnchor.constraint(equalTo: alertView.trailingAnchor, constant: -20),
            submitButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 12),
            submitButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor),
            submitButton.heightAnchor.constraint(equalToConstant: 48),
            submitButton.bottomAnchor.constraint(equalTo: alertView.bottomAnchor, constant: -24)
        ])
    }

    // MARK: - Animations
    private func animateIn() {
        alertView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        alertView.alpha = 0

        UIView.animate(
            withDuration: 0.35,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: [.curveEaseOut]
        ) {
            self.dimView.alpha = 1
            self.alertView.transform = .identity
            self.alertView.alpha = 1
        }
    }

    private func animateOut(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.25, animations: {
            self.alertView.alpha = 0
            self.alertView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            self.dimView.alpha = 0
        }) { _ in
            completion?()
        }
    }

    // MARK: - Actions
    @objc private func cancelPressed() { dismissWithoutAction() }

    @objc private func backgroundTapped(_ gr: UITapGestureRecognizer) {
        let point = gr.location(in: view)
        guard !alertView.frame.contains(point) else { return }
        dismissWithoutAction()
    }

    private func dismissWithoutAction() {
        animateOut { [weak self] in
            self?.onDismiss?()
            self?.dismiss(animated: false, completion: nil)
        }
    }

    @objc private func submitPressed() {
        let rating = starsView.rating
        onSubmit?(rating)
        AppSettings.shared.isSubmittedRating = true

        // Every rating gets the same treatment. Routing only 4-5 star raters to the App Store
        // and quietly swallowing the rest is review gating — App Store Review Guideline 1.1.7
        // prohibits filtering feedback this way, and it is grounds for rejection.
        requestInAppReview()

        UIView.animate(withDuration: 0.2) { self.thanksLabel.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.animateOut { [weak self] in
                self?.dismiss(animated: false, completion: nil)
            }
        }
    }

    private func requestInAppReview() {
        guard let scene = view.window?.windowScene else { return }

        if #available(iOS 18.0, *) {
            AppStore.requestReview(in: scene)
        } else {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}

// MARK: - Star Rating View

final class StarRatingView: UIStackView {
    var onChange: ((Int) -> Void)?

    private let total: Int
    private(set) var rating: Int {
        didSet { updateStars() }
    }

    private var buttons: [UIButton] = []

    // Gold color for stars
    private let starColor = UIColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)

    init(stars: Int = 5, initial: Int = 5) {
        self.total = max(1, stars)
        self.rating = max(1, min(stars, initial))
        super.init(frame: .zero)

        axis = .horizontal
        alignment = .center
        distribution = .fillEqually
        spacing = 8
        isLayoutMarginsRelativeArrangement = false

        setupStars()
        updateStars()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setInitialRating(_ value: Int) {
        rating = max(1, min(total, value))
    }

    private func setupStars() {
        for i in 1...total {
            let b = UIButton(type: .system)
            b.tag = i
            b.tintColor = starColor

            let config = UIImage.SymbolConfiguration(pointSize: 36, weight: .semibold)
            b.setPreferredSymbolConfiguration(config, forImageIn: .normal)

            b.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)

            buttons.append(b)
            addArrangedSubview(b)
        }
    }

    private func updateStars() {
        for (idx, b) in buttons.enumerated() {
            let filled = idx < rating
            b.setImage(UIImage(systemName: filled ? "star.fill" : "star"), for: .normal)
            b.tintColor = filled ? starColor : AppColors.textSecondary.withAlphaComponent(0.25)

            b.accessibilityLabel = "\(idx + 1) star\(idx == 0 ? "" : "s")"
            b.accessibilityTraits = [.button]
        }
    }

    @objc private func tap(_ sender: UIButton) {
        rating = sender.tag
        onChange?(rating)
    }
}
