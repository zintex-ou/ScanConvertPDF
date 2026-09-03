//
//  EmptyStateView.swift
//  ScanConvertPDF
//
//  Created by Developer
//

import UIKit

final class EmptyStateView: UIView {

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "You don't have any documents"
        label.font = AppFonts.semibold(20)
        label.textColor = AppColors.primary
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Tap the + button to add/scan a document."
        label.font = AppFonts.regular(14)
        label.textColor = AppColors.textSecondary
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var arrowImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.image = UIImage(systemName: "arrow.down")
        iv.tintColor = AppColors.primary.withAlphaComponent(0.5)
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(arrowImageView)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),

            arrowImageView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 30),
            arrowImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            arrowImageView.widthAnchor.constraint(equalToConstant: 24),
            arrowImageView.heightAnchor.constraint(equalToConstant: 50),
            arrowImageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        animateArrow()
    }

    private func animateArrow() {
        UIView.animate(withDuration: 1.0,
                       delay: 0,
                       options: [.repeat, .autoreverse, .curveEaseInOut]) {
            self.arrowImageView.transform = CGAffineTransform(translationX: 0, y: 10)
        }
    }
}
