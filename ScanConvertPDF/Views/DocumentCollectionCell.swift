//
//  DocumentCollectionCell.swift
//  ScanConvertPDF
//

import UIKit

protocol DocumentCollectionCellDelegate: AnyObject {
    func documentCellDidTapMore(_ cell: DocumentCollectionCell)
}

final class DocumentCollectionCell: UICollectionViewCell {

    static let identifier = "DocumentCollectionCell"

    weak var delegate: DocumentCollectionCellDelegate?

    /// зручно для popover на iPad (sourceView)
    var moreAnchorView: UIView { moreButton }

    // MARK: - UI

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

    private let thumbImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(white: 0.95, alpha: 1)
        iv.layer.cornerRadius = 10
        iv.layer.cornerCurve = .continuous
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = AppFonts.bold(16)
        l.textColor = AppColors.textPrimary
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingTail
        return l
    }()

    private let subtitleLabel: UILabel = {
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
        s.spacing = 4
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
        delegate?.documentCellDidTapMore(self)
    }

    private func setupUI() {
        contentView.backgroundColor = .clear

        contentView.addSubview(cardView)
        cardView.addSubview(thumbImageView)
        cardView.addSubview(moreButton)
        cardView.addSubview(textStack)

        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            thumbImageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 14),
            thumbImageView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            thumbImageView.widthAnchor.constraint(equalToConstant: 44),
            thumbImageView.heightAnchor.constraint(equalToConstant: 44),

            moreButton.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -6),
            moreButton.widthAnchor.constraint(equalToConstant: 44),
            moreButton.heightAnchor.constraint(equalToConstant: 44),

            textStack.leadingAnchor.constraint(equalTo: thumbImageView.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: moreButton.leadingAnchor, constant: -8),
            textStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor)
        ])
    }

    // MARK: - Configure (Core Data)

    func configure(with document: CDDocument) {
        let name = document.name ?? "Untitled"

        // title: "07 Feb, Document 4" style
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "dd MMM"

        let dateText = document.createdAt.map { df.string(from: $0) } ?? ""
        titleLabel.text = dateText.isEmpty ? name : "\(dateText), \(name)"

        let pageCount = Int(document.pageCount)
        subtitleLabel.text = "\(pageCount) page" + (pageCount == 1 ? "" : "s")

        if let data = document.thumbnailData, let image = UIImage(data: data) {
            thumbImageView.image = image
        } else {
            thumbImageView.image = nil
        }

        applyAppearance(animated: false)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        delegate = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
        thumbImageView.image = nil
        applyAppearance(animated: false)
    }

    // MARK: - Highlight

    override var isHighlighted: Bool {
        didSet { applyAppearance(animated: true) }
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
    
    func showSelectionIndicator(_ show: Bool) {
        if show {
            cardView.layer.borderWidth = isSelected ? 2 : 0
            cardView.layer.borderColor = isSelected ? AppColors.primary.cgColor : UIColor.clear.cgColor
        } else {
            cardView.layer.borderWidth = 0
            cardView.layer.borderColor = UIColor.clear.cgColor
        }
    }
    
    func setSelectionMode(_ enabled: Bool) {
        moreButton.isEnabled = !enabled
        moreButton.alpha = enabled ? 0.3 : 1.0
    }
}
