//
//  DefaultOnboardingViewController.swift
//  ScanConvertPDF
//
//  Created by Developer on 22.01.2026.
//

import UIKit

struct OnboardingPage {
    let title: String
    let description: String
    let illustrationName: String
    let buttonTitle: String
}

final class DefaultOnboardingViewController: UIViewController {

    // MARK: - Data

    private let pages: [OnboardingPage] = [
        .init(
            title: "Welcome to PDF Scan & Convert Pro",
            description: "Scan, import, and convert your files into clean, shareable PDFs in seconds.",
            illustrationName: "onboarding-welcome-image",
            buttonTitle: "Next"
        ),
        .init(
            title: "Scan & Capture",
            description: "Use Scan or Camera to capture documents. We’ll help you keep pages clear and readable.",
            illustrationName: "onboarding-scan-image",
            buttonTitle: "Next"
        ),
        .init(
            title: "Import From Anywhere",
            description: "Add pages from your Gallery, import existing Documents, or turn a Web Page into a PDF.",
            illustrationName: "onboarding-import-image",
            buttonTitle: "Next"
        ),
        .init(
            title: "Convert to PDF",
            description: "Turn your pages into a single PDF - ready to share, print or save.",
            illustrationName: "onboarding-convert-image",
            buttonTitle: "Next"
        ),
        .init(
            title: "Ready to Start?",
            description: "Tap the + button to add content: Scan, Camera, Gallery, Web Page, or Documents.",
            illustrationName: "onboarding-start-image",
            buttonTitle: "Get Started"
        )
    ]

    private var currentIndex: Int = 0

    // callback
    var onComplete: (() -> Void)?

    // MARK: - Config
    private let showCloseButton: Bool

    // MARK: - UI

    private let topBar = UIView()
    private let backButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let pageControl = UIPageControl()
    private let primaryButton = UIButton(type: .system)
    private let imageShadowContainer = UIView()

    // MARK: - Init

    init(showCloseButton: Bool = false) {
        self.showCloseButton = showCloseButton
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AppColors.background

        setupUI()
        layout()
        applyPage(animated: false)
    }

    // MARK: - Setup

    private func setupUI() {
        // topBar
        topBar.backgroundColor = .clear
        view.addSubview(topBar)
        topBar.translatesAutoresizingMaskIntoConstraints = false

        // back
        backButton.setTitle("Back", for: .normal)
        backButton.setTitleColor(AppColors.textSecondary, for: .normal)
        backButton.titleLabel?.font = AppFonts.semibold(16)
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        topBar.addSubview(backButton)
        backButton.translatesAutoresizingMaskIntoConstraints = false

        // close
        closeButton.setTitle("Close", for: .normal)
        closeButton.setTitleColor(AppColors.textSecondary, for: .normal)
        closeButton.titleLabel?.font = AppFonts.semibold(16)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        topBar.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // image shadow container
        imageShadowContainer.backgroundColor = .clear
        imageShadowContainer.layer.shadowColor = UIColor.black.cgColor
        imageShadowContainer.layer.shadowOpacity = 0.12
        imageShadowContainer.layer.shadowRadius = 12
        imageShadowContainer.layer.shadowOffset = CGSize(width: 0, height: 6)
        imageShadowContainer.layer.masksToBounds = false
        view.addSubview(imageShadowContainer)
        imageShadowContainer.translatesAutoresizingMaskIntoConstraints = false

        // image
        imageView.contentMode = .scaleAspectFit
        imageShadowContainer.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: imageShadowContainer.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: imageShadowContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageShadowContainer.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageShadowContainer.bottomAnchor)
        ])

        // labels
        titleLabel.font = AppFonts.bold(28)
        titleLabel.textColor = AppColors.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        view.addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        descriptionLabel.font = AppFonts.regular(16)
        descriptionLabel.textColor = AppColors.textSecondary
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        view.addSubview(descriptionLabel)
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        // page control
        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = AppColors.primary
        pageControl.pageIndicatorTintColor = AppColors.textSecondary.withAlphaComponent(0.45)
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
        view.addSubview(pageControl)
        pageControl.translatesAutoresizingMaskIntoConstraints = false

        // primary button
        primaryButton.backgroundColor = AppColors.primary
        primaryButton.setTitleColor(.white, for: .normal)
        primaryButton.titleLabel?.font = AppFonts.bold(20)
        primaryButton.layer.cornerRadius = AppConstants.cornerRadius
        primaryButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        view.addSubview(primaryButton)
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - Layout

    private func layout() {
        NSLayoutConstraint.activate([
            // topBar
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 44),

            // back
            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 24),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            backButton.heightAnchor.constraint(equalToConstant: 40),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            // close
            closeButton.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -24),
            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.heightAnchor.constraint(equalToConstant: 40),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            // primary button
            primaryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            primaryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            primaryButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            primaryButton.heightAnchor.constraint(equalToConstant: 54),

            // page control
            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: primaryButton.topAnchor, constant: -24),
            pageControl.heightAnchor.constraint(equalToConstant: 20),

            // image
            imageView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 16),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.38),

            // title
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // description
            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            descriptionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            descriptionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            descriptionLabel.bottomAnchor.constraint(lessThanOrEqualTo: pageControl.topAnchor, constant: -16)
        ])
    }

    // MARK: - Apply Page

    private func applyPage(animated: Bool) {
        let page = pages[currentIndex]

        let updates = { [weak self] in
            guard let self else { return }

            self.titleLabel.text = page.title
            self.descriptionLabel.text = page.description
            self.imageView.image = UIImage(named: page.illustrationName)

            self.primaryButton.setTitle(page.buttonTitle, for: .normal)
            self.pageControl.currentPage = self.currentIndex

            self.backButton.isHidden = self.currentIndex == 0
            self.closeButton.isHidden = !self.showCloseButton
        }

        if animated {
            UIView.transition(with: view, duration: 0.25, options: .transitionCrossDissolve, animations: updates)
        } else {
            updates()
        }
    }

    // MARK: - Actions

    @objc private func nextTapped() {
        if currentIndex < pages.count - 1 {
            currentIndex += 1
            applyPage(animated: true)
            animateButton(primaryButton)
        } else {
            finish()
        }
    }

    @objc private func backTapped() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        applyPage(animated: true)
        animateButton(backButton)
    }

    @objc private func closeTapped() {
        finish()
    }

    @objc private func pageControlChanged() {
        currentIndex = pageControl.currentPage
        applyPage(animated: true)
    }

    private func finish() {
        if let onComplete {
            onComplete()
        } else {
            dismiss(animated: true)
        }
    }

    private func animateButton(_ button: UIButton) {
        UIView.animate(withDuration: 0.1, animations: {
            button.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
            button.layer.shadowColor = AppColors.primary.cgColor
            button.layer.shadowOpacity = 0.35
            button.layer.shadowRadius = 12
            button.layer.shadowOffset = .zero
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                button.transform = .identity
                button.layer.shadowOpacity = 0
            }
        }
    }
}
