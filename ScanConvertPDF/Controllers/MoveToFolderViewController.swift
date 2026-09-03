//
//  MoveToFolderViewController.swift
//  ScanConvertPDF
//
//  Created by Developer on 20.01.2026.
//

import Foundation
import UIKit
import CoreData

final class MoveToFolderViewController: UIViewController {

    // MARK: - UI Model

    private struct Item {
        let isHome: Bool
        let folder: CDFolder?   // nil == Home
        let title: String
        let dateText: String
        let count: Int
    }

    // MARK: - Dependencies

    private let context: NSManagedObjectContext
    private var folders: [CDFolder] = []
    private var items: [Item] = []
    private let currentFolder: CDFolder?
    /// Callback: folder == nil => "Home / No Folder"
    var onPick: ((CDFolder?) -> Void)?

    // MARK: - UI

    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = true
        cv.alwaysBounceVertical = true
        cv.delegate = self
        cv.dataSource = self
        cv.contentInsetAdjustmentBehavior = .always
        cv.register(FolderCollectionCell.self, forCellWithReuseIdentifier: FolderCollectionCell.identifier)
        return cv
    }()
    
    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 2
        label.textColor = AppColors.textSecondary
        label.font = AppFonts.regular(16)
        label.text = "No folders yet.\nChoose Home or create a folder."
        label.isHidden = true
        return label
    }()

    // MARK: - Init

    init(currentFolder: CDFolder?, context: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.currentFolder = currentFolder
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNav()
        loadData()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = AppColors.background
        view.addSubview(collectionView)
        view.addSubview(emptyStateLabel)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24)
        ])
    }

    private func setupNav() {
        title = "Move to Folder"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        navigationItem.leftBarButtonItem?.tintColor = AppColors.primary
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    private func createLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            // item = full width, height = 80 (як DocumentCollectionCell)
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(80)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(80)
            )
            let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16)
            section.interGroupSpacing = 12
            return section
        }
        return layout
    }

    // MARK: - Data

    private func loadData() {
        // 1) беремо всі папки
        let allFolders = fetchFolders()

        // 2) якщо ми зараз в якійсь папці — не показуємо її
        if let currentId = currentFolder?.id {
            folders = allFolders.filter { $0.id != currentId }
        } else {
            folders = allFolders
        }

        var result: [Item] = []

        // 3) Home показуємо ТІЛЬКИ якщо ми зараз НЕ в Home
        if currentFolder != nil {
            let homeCount = fetchNoFolderDocumentsCount()
            result.append(Item(isHome: true, folder: nil, title: "Home", dateText: "", count: homeCount))
        }

        // 4) додаємо папки
        let df = DateFormatter()
        df.dateFormat = "dd/MM/yyyy"

        let folderItems: [Item] = folders.map { f in
            let count = (f.documents as? Set<CDDocument>)?.count ?? 0
            let dateText = f.createdAt.map { df.string(from: $0) } ?? ""

            return Item(
                isHome: false,
                folder: f,
                title: f.name ?? "Untitled",
                dateText: dateText,
                count: count
            )
        }

        result.append(contentsOf: folderItems)

        items = result
        emptyStateLabel.isHidden = !folders.isEmpty
        collectionView.reloadData()
    }

    private func fetchFolders() -> [CDFolder] {
        let req: NSFetchRequest<CDFolder> = CDFolder.fetchRequest()
        req.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return (try? context.fetch(req)) ?? []
    }

    private func fetchNoFolderDocumentsCount() -> Int {
        let req: NSFetchRequest<CDDocument> = CDDocument.fetchRequest()
        req.predicate = NSPredicate(format: "folder == nil")
        return (try? context.count(for: req)) ?? 0
    }
}

// MARK: - UICollectionViewDataSource

extension MoveToFolderViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: FolderCollectionCell.identifier,
            for: indexPath
        ) as! FolderCollectionCell

        cell.delegate = nil
        cell.setSelectionMode(false)
        cell.showSelectionIndicator(false)

        let item = items[indexPath.item]

        if item.isHome {
            cell.configureCustom(
                title: item.title,
                dateText: item.dateText,
                documentCount: item.count,
                iconImage: UIImage(named: "home-folder-image")
            )
        } else {
            cell.configureCustom(
                title: item.title,
                dateText: item.dateText,
                documentCount: item.count,
                iconImage: UIImage(named: "folder-image")
            )
        }

        cell.moreAnchorView.isHidden = true
        cell.moreAnchorView.isUserInteractionEnabled = false
        cell.moreAnchorView.alpha = 0.0

        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? FolderCollectionCell {
            cell.isHighlighted = true
        }
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        if let cell = collectionView.cellForItem(at: indexPath) as? FolderCollectionCell {
            cell.isHighlighted = false
        }
    }
}

// MARK: - UICollectionViewDelegate

extension MoveToFolderViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let item = items[indexPath.item]
        onPick?(item.folder) // nil => Home
        dismiss(animated: true)
    }
}
