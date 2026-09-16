//
//  ReorderPagesViewController.swift
//  ScanConvertPDF
//
//  Drag-to-reorder + delete individual pages of an existing PDF document.
//

import UIKit
import PDFKit

final class ReorderPagesViewController: UIViewController {

    // MARK: - Properties

    private var pages: [PDFPage]
    private let onSave: (PDFDocument) -> Void

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.minimumLineSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.register(PageThumbnailCell.self, forCellWithReuseIdentifier: PageThumbnailCell.identifier)
        cv.dataSource = self
        cv.delegate = self
        return cv
    }()

    private lazy var longPressGesture: UILongPressGestureRecognizer = {
        UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
    }()

    // MARK: - Init

    init(pdfDocument: PDFDocument, onSave: @escaping (PDFDocument) -> Void) {
        self.pages = (0..<pdfDocument.pageCount).compactMap { pdfDocument.page(at: $0) }
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    private func setupUI() {
        view.backgroundColor = AppColors.background
        title = "Reorder Pages"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped)
        )
        let doneButton = UIBarButtonItem(
            title: "Done", style: .done, target: self, action: #selector(doneTapped)
        )
        doneButton.tintColor = AppColors.primary
        navigationItem.rightBarButtonItem = doneButton

        collectionView.addGestureRecognizer(longPressGesture)
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        guard !pages.isEmpty else {
            dismiss(animated: true)
            return
        }
        let newDocument = PDFDocument()
        for (index, page) in pages.enumerated() {
            newDocument.insert(page, at: index)
        }
        onSave(newDocument)
        dismiss(animated: true)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let indexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)) else { return }
            collectionView.beginInteractiveMovementForItem(at: indexPath)
        case .changed:
            collectionView.updateInteractiveMovementTargetPosition(gesture.location(in: collectionView))
        case .ended:
            collectionView.endInteractiveMovement()
            // Cell contents (page-number badges) aren't recalculated by the
            // move itself, so refresh once the move animation settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.collectionView.reloadData()
            }
        default:
            collectionView.cancelInteractiveMovement()
        }
    }

    private func deletePage(at index: Int) {
        guard pages.count > 1, index < pages.count else { return }
        pages.remove(at: index)
        collectionView.performBatchUpdates {
            collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
        } completion: { [weak self] _ in
            self?.collectionView.reloadData()
        }
    }
}

// MARK: - UICollectionViewDataSource

extension ReorderPagesViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        pages.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: PageThumbnailCell.identifier, for: indexPath
        ) as? PageThumbnailCell else {
            return UICollectionViewCell()
        }

        let page = pages[indexPath.item]
        let thumb = page.thumbnail(of: CGSize(width: 200, height: 280), for: .mediaBox)
        cell.configure(image: thumb, pageNumber: indexPath.item + 1, canDelete: pages.count > 1)
        cell.onDelete = { [weak self] in self?.deletePage(at: indexPath.item) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        true
    }

    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let moved = pages.remove(at: sourceIndexPath.item)
        pages.insert(moved, at: destinationIndexPath.item)
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension ReorderPagesViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let spacing: CGFloat = 16 * 2 + 12
        let width = (collectionView.bounds.width - spacing) / 2
        return CGSize(width: width, height: width * 1.4)
    }
}

// MARK: - PageThumbnailCell

private final class PageThumbnailCell: UICollectionViewCell {

    static let identifier = "PageThumbnailCell"

    var onDelete: (() -> Void)?

    private let cardView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = AppColors.cellBackground
        v.layer.cornerRadius = 14
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
        return v
    }()

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.backgroundColor = UIColor(white: 0.95, alpha: 1)
        return iv
    }()

    private let pageNumberBadge: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        v.layer.cornerRadius = 10
        v.layer.masksToBounds = true
        return v
    }()

    private let pageNumberLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppFonts.medium(12)
        label.textColor = .white
        return label
    }()

    private let deleteButton: UIButton = {
        let b = UIButton(type: .system)
        b.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        b.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: config), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        b.layer.cornerRadius = 12
        return b
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        contentView.addSubview(cardView)
        cardView.addSubview(imageView)
        cardView.addSubview(pageNumberBadge)
        pageNumberBadge.addSubview(pageNumberLabel)
        cardView.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
            cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: cardView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            pageNumberBadge.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 8),
            pageNumberBadge.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -8),

            pageNumberLabel.topAnchor.constraint(equalTo: pageNumberBadge.topAnchor, constant: 4),
            pageNumberLabel.bottomAnchor.constraint(equalTo: pageNumberBadge.bottomAnchor, constant: -4),
            pageNumberLabel.leadingAnchor.constraint(equalTo: pageNumberBadge.leadingAnchor, constant: 8),
            pageNumberLabel.trailingAnchor.constraint(equalTo: pageNumberBadge.trailingAnchor, constant: -8),

            deleteButton.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 6),
            deleteButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -6),
            deleteButton.widthAnchor.constraint(equalToConstant: 24),
            deleteButton.heightAnchor.constraint(equalToConstant: 24)
        ])

        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
    }

    @objc private func deleteTapped() {
        onDelete?()
    }

    func configure(image: UIImage?, pageNumber: Int, canDelete: Bool) {
        imageView.image = image
        pageNumberLabel.text = "\(pageNumber)"
        deleteButton.isHidden = !canDelete
    }
}
