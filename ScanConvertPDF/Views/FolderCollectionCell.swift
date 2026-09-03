//
//  FolderCollectionCell.swift
//  ScanConvertPDF
//

import UIKit

protocol FolderCollectionCellDelegate: AnyObject {
    func folderCellDidTapMore(_ cell: FolderCollectionCell)
}

final class FolderCollectionCell: UICollectionViewCell {

    static let identifier = "FolderCollectionCell"

    weak var delegate: FolderCollectionCellDelegate?

    /// зручно для popover на iPad (sourceView)
    var moreAnchorView: UIView { moreButton }

    // MARK: - UI

    private let cardView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = AppColors.cellBackground
        v.layer.cornerRadius = 22
        v.layer.cornerCurve = .continuous

        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOffset = CGSize(width: 0, height: 1)
        v.layer.shadowRadius = 1
        v.layer.shadowOpacity = 0.10

        return v
    }()

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.image = UIImage(named: "folder-image")
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = AppFonts.bold(18)
        l.textColor = AppColors.textPrimary
        l.numberOfLines = 1
        return l
    }()

    private let dateLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = AppFonts.regular(13)
        l.textColor = AppColors.textSecondary
        l.numberOfLines = 1
        return l
    }()

    private let itemsLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = AppFonts.regular(13)
        l.textColor = AppColors.textSecondary
        l.numberOfLines = 1
        return l
    }()

    private let moreButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        b.setImage(UIImage(systemName: "ellipsis", withConfiguration: cfg), for: .normal)
        b.tintColor = AppColors.primary
        b.contentEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        b.isExclusiveTouch = true
        return b
    }()

    private let textStack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.alignment = .leading
        s.distribution = .fill
        s.spacing = 6
        return s
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)
        applyAppearance(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func moreTapped() {
        delegate?.folderCellDidTapMore(self)
    }

    private func setupUI() {
        contentView.backgroundColor = .clear

        contentView.addSubview(cardView)
        cardView.addSubview(iconImageView)
        cardView.addSubview(moreButton)

        cardView.addSubview(textStack)
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(dateLabel)
        textStack.addArrangedSubview(itemsLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            iconImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            iconImageView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 58),
            iconImageView.heightAnchor.constraint(equalToConstant: 58),

            moreButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 6),
            moreButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -6),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 14),
            textStack.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
        ])
    }
    

    // MARK: - Configure (Core Data)

    func configure(with folder: CDFolder, documentCount: Int) {
        titleLabel.text = folder.name ?? "Untitled"

        if let createdAt = folder.createdAt {
            let df = DateFormatter()
            df.dateFormat = "dd/MM/yyyy"
            dateLabel.text = df.string(from: createdAt)
        } else {
            dateLabel.text = ""
        }

        itemsLabel.text = "\(documentCount) item" + (documentCount == 1 ? "" : "s")
        applyAppearance(animated: false)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        delegate = nil
        titleLabel.text = nil
        dateLabel.text = nil
        itemsLabel.text = nil
        iconImageView.image = UIImage(named: "folder-image")
        applyAppearance(animated: false)
    }

    // MARK: - press highlight

    override var isHighlighted: Bool {
        didSet { applyAppearance(animated: true) }
    }
    
    private func applyAppearance(animated: Bool) {
        let changes = {
            if self.isHighlighted {
                self.cardView.backgroundColor = AppColors.cellBackgroundHighlighted
                self.titleLabel.textColor = .white
                self.dateLabel.textColor = UIColor.white.withAlphaComponent(0.75)
                self.itemsLabel.textColor = UIColor.white.withAlphaComponent(0.75)
                self.moreButton.tintColor = .white

                self.cardView.transform = CGAffineTransform(scaleX: 0.985, y: 0.985)
                // self.cardView.layer.shadowOpacity = 0.05
            } else {
                self.cardView.backgroundColor = AppColors.cellBackground
                self.titleLabel.textColor = AppColors.textPrimary
                self.dateLabel.textColor = AppColors.textSecondary
                self.itemsLabel.textColor = AppColors.textSecondary
                self.moreButton.tintColor = AppColors.primary

                self.cardView.transform = .identity
                // self.cardView.layer.shadowOpacity = 0.10
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
    
    func showSelectionIndicator(_ show: Bool) {
        if show {
            // Показати checkmark або border
            contentView.layer.borderWidth = isSelected ? 2 : 0
            contentView.layer.borderColor = isSelected ? AppColors.primary.cgColor : UIColor.clear.cgColor
        } else {
            contentView.layer.borderWidth = 0
        }
    }
    
    func setSelectionMode(_ enabled: Bool) {

        // moreButton вимкнений
        moreButton.isUserInteractionEnabled = !enabled
        moreButton.isEnabled = !enabled
        moreButton.alpha = enabled ? 0.3 : 1.0

        // візуально вся комірка "неактивна"
        cardView.alpha = enabled ? 0.5 : 1.0

        // (опційно) трохи прибрати тінь, щоб було як disabled
        cardView.layer.shadowOpacity = enabled ? 0.0 : 0.10

        // важливо: щоб при затисканні не було highlight-ефекту
        isUserInteractionEnabled = !enabled
    }
    
    func configureCustom(title: String, dateText: String, documentCount: Int, iconImage: UIImage?) {
        titleLabel.text = title
        dateLabel.text = dateText
        itemsLabel.text = "\(documentCount) item" + (documentCount == 1 ? "" : "s")
        iconImageView.image = iconImage
        applyAppearance(animated: false)
    }
}
