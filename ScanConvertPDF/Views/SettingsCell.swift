//
//  SettingsCell.swift
//  ScanConvertPDF
//
//  Created by Developer on 22.01.2026.
//

import UIKit


final class SettingsCell: UITableViewCell {

    static let identifier = "SettingsCell"

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

    private let chevronView: UIImageView = {
        let iv = UIImageView(image: UIImage(systemName: "chevron.right"))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = .systemGray3
        return iv
    }()

    private let symbolConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular, scale: .medium)

    // MARK: - Init

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        applyAppearance(animated: false)
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
        cardView.addSubview(chevronView)

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

            chevronView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -16),
            chevronView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 10),

            titleLabel.leadingAnchor.constraint(equalTo: iconContainerView.trailingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -12)
        ])
    }

    // MARK: - Configure

    func configure(with title: String, icon: String, iconColor: UIColor) {
        titleLabel.text = title

        iconImageView.image = UIImage(systemName: icon, withConfiguration: symbolConfig)
        iconImageView.tintColor = iconColor

        iconContainerView.backgroundColor = iconColor.withAlphaComponent(0.14)
        iconContainerView.layer.borderColor = iconColor.withAlphaComponent(0.28).cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        iconImageView.image = nil
        iconImageView.tintColor = nil
        iconContainerView.backgroundColor = nil
        iconContainerView.layer.borderColor = nil
        applyAppearance(animated: false)
    }

    // MARK: - Highlight

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        applyAppearance(animated: animated)
    }
    
    private func applyAppearance(animated: Bool) {
        let changes = {
            if self.isHighlighted {
                self.cardView.backgroundColor = AppColors.cellBackgroundHighlighted
                self.cardView.transform = CGAffineTransform(scaleX: 0.99, y: 0.99)
            } else {
                self.cardView.backgroundColor = AppColors.cellBackground
                self.cardView.transform = .identity
            }
        }

        if animated {
            UIView.animate(withDuration: 0.12,
                           delay: 0,
                           options: [.allowUserInteraction, .curveEaseOut],
                           animations: changes)
        } else {
            changes()
        }
    }
}
