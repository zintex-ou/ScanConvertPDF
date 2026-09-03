//
//  ToastAlertViewController.swift
//  ScanConvertPDF
//
//  Created by Developer on 21.01.2026.
//

import Foundation
import UIKit

/// Компактний карточний алерт з автозакриттям.
final class ToastAlertViewController: UIViewController {

    private let message: String
    private let iconName: String
    private let autoDismissAfter: TimeInterval
    private let onDismiss: (() -> Void)?

    init(message: String = "Done",
         iconName: String = "checkmark-image",
         autoDismissAfter: TimeInterval = 1.5,
         onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.iconName = iconName
        self.autoDismissAfter = autoDismissAfter
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    static func present(over presenter: UIViewController,
                        message: String = "Done",
                        iconName: String = "checkmark-image",
                        autoDismissAfter: TimeInterval = 1.0,
                        onDismiss: (() -> Void)? = nil) -> ToastAlertViewController {
        let vc = ToastAlertViewController(message: message,
                                         iconName: iconName,
                                         autoDismissAfter: autoDismissAfter,
                                         onDismiss: onDismiss)
        presenter.present(vc, animated: true)
        return vc
    }

    // MARK: - UI

    private let dimView = UIView()
    private let cardView = UIView()
    private let iconView = UIImageView()
    private let messageLabel = UILabel()

    private var autoDismissWorkItem: DispatchWorkItem?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        layoutUI()
        animateIn()
        scheduleAutoDismiss()
    }

    deinit { autoDismissWorkItem?.cancel() }

    // MARK: - Build UI

    private func buildUI() {
        view.backgroundColor = .clear

        // Background dim
        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        dimView.alpha = 0
        dimView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimView)

        // Card (white)
        cardView.backgroundColor = AppColors.cellBackground
        cardView.layer.cornerRadius = 20
        cardView.layer.masksToBounds = false
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.08
        cardView.layer.shadowRadius = 20
        cardView.layer.shadowOffset = CGSize(width: 0, height: 6)
        cardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardView)

        // Icon (red)
        iconView.image = UIImage(named: iconName)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(iconView)

        // Text (gray)
        messageLabel.text = message
        messageLabel.textAlignment = .center
        messageLabel.textColor = AppColors.textSecondary
        messageLabel.font = UIFont(name: "Onest-Bold", size: 25)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(messageLabel)

        // Tap to dismiss
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissTapped))
        view.addGestureRecognizer(tap)
    }

    private func layoutUI() {
        NSLayoutConstraint.activate([
            // dimView
            dimView.topAnchor.constraint(equalTo: view.topAnchor),
            dimView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // cardView
            cardView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            cardView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            cardView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            cardView.heightAnchor.constraint(equalToConstant: 200),

            // iconView
            iconView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 16),
            iconView.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 124),
            iconView.heightAnchor.constraint(equalToConstant: 124),

            // messageLabel
            messageLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            messageLabel.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Animations

    private func animateIn() {
        cardView.transform = CGAffineTransform(scaleX: 1.06, y: 1.06)
        cardView.alpha = 0
        iconView.alpha = 0
        messageLabel.alpha = 0

        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut]) {
            self.dimView.alpha = 1
            self.cardView.transform = .identity
            self.cardView.alpha = 1
            self.iconView.alpha = 1
            self.messageLabel.alpha = 1
        }
    }

    private func animateOut(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.2, animations: {
            self.cardView.alpha = 0
            self.dimView.alpha = 0
        }) { _ in completion?() }
    }

    // MARK: - Dismiss

    private func scheduleAutoDismiss() {
        guard autoDismissAfter > 0 else { return }
        let work = DispatchWorkItem { [weak self] in self?.dismissAnimated() }
        autoDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoDismissAfter, execute: work)
    }

    @objc private func dismissTapped() {
        dismissAnimated()
    }

    func dismissAnimated() {
        autoDismissWorkItem?.cancel()
        animateOut { [weak self] in
            guard let self else { return }
            self.dismiss(animated: false) { [weak self] in
                self?.onDismiss?()
            }
        }
    }
}
