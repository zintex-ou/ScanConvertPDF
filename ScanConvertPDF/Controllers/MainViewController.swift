//
//  MainViewController.swift
//  ScanConvertPDF
//
//  Created by Developer
//

import UIKit
import PhotosUI
import VisionKit
import CropViewController
import UniformTypeIdentifiers
import CoreData
import PDFKit

final class MainViewController: UIViewController {

    // MARK: - Core Data

    private let context = CoreDataStack.shared.context

    // MARK: - Properties (Core Data objects)

    private var documents: [CDDocument] = []
    private var folders: [CDFolder] = []
    private var currentFolderId: UUID? // nil = "No Folder" документи

    private var contextObserver: NSObjectProtocol?
    
    // MARK: - Selection Mode (тільки для документів)
    
    private var isSelectionMode = false
    private var selectedDocuments: Set<UUID> = []
    
    // MARK: - Search
    private var currentSearchQuery: String = ""

    // MARK: - UI Elements
    
    // One collection view with 2 sections: 0 - folders (horizontal), 1 - documents (vertical)
    private lazy var collectionView: UICollectionView = {
        let cv = UICollectionView(frame: .zero, collectionViewLayout: createLayout())
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.dataSource = self
        cv.showsHorizontalScrollIndicator = false
        cv.alwaysBounceVertical = true
        cv.keyboardDismissMode = .onDrag
        cv.contentInsetAdjustmentBehavior = .always
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(FolderCollectionCell.self, forCellWithReuseIdentifier: FolderCollectionCell.identifier)
        cv.register(DocumentCollectionCell.self, forCellWithReuseIdentifier: DocumentCollectionCell.identifier)
        cv.register(DocumentsHeaderView.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: DocumentsHeaderView.reuseIdentifier)
        return cv
    }()
    
    private lazy var searchView: SearchFieldView = {
        let v = SearchFieldView()
        v.translatesAutoresizingMaskIntoConstraints = false

        v.onTextChanged = { [weak self] text in
            guard let self else { return }
            self.currentSearchQuery = text
            if text.isEmpty {
                self.documents = self.fetchDocuments(folderId: self.currentFolderId)
                self.collectionView.reloadSections(IndexSet(integer: 1))
            }
        }

        v.onSearchTapped = { [weak self] text in
            guard let self else { return }
            self.currentSearchQuery = text

            if text.isEmpty {
                self.documents = self.fetchDocuments(folderId: self.currentFolderId)
            } else {
                let allDocs = self.fetchDocuments(folderId: self.currentFolderId)
                let q = text.lowercased()
                self.documents = allDocs.filter { ($0.name?.lowercased().contains(q) ?? false) }
            }

            self.applySavedSortAndReloadDocuments()

            self.collectionView.reloadSections(IndexSet(integer: 1))
            self.view.endEditing(true)
        }

        return v
    }()
    
    private lazy var controlsStackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private lazy var selectButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Select", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = AppColors.primary
        button.layer.cornerRadius = 20
        button.titleLabel?.font = AppFonts.medium(16)
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 24, bottom: 10, right: 24)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(selectButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var sortButton: UIButton = {
        let button = CircularIconButton(type: .system)

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "arrow.up.arrow.down")
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium, scale: .medium)

        button.configuration = config
        button.tintColor = .white
        button.backgroundColor = AppColors.primary

        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.widthAnchor.constraint(equalTo: button.heightAnchor).isActive = true

        button.addTarget(self, action: #selector(sortButtonTapped), for: .touchUpInside)
        return button
    }()

    // Action buttons (показуються в режимі вибору)
    private lazy var shareActionButton: UIButton = {
        let button = createActionButton(
            icon: "square.and.arrow.up",
            action: #selector(shareSelectedTapped)
        )
        button.isHidden = true
        return button
    }()
    
    private lazy var moveActionButton: UIButton = {
        let button = createActionButton(
            icon: "folder",
            action: #selector(moveSelectedTapped)
        )
        button.isHidden = true
        return button
    }()
    
    private lazy var deleteActionButton: UIButton = {
        let button = createActionButton(
            icon: "trash",
            action: #selector(deleteSelectedTapped)
        )
        button.isHidden = true
        return button
    }()
    
    private func createActionButton(icon: String, action: Selector) -> UIButton {
        let button = CircularIconButton(type: .system)

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: icon)
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .medium, scale: .medium)

        button.configuration = config
        button.tintColor = .white
        button.backgroundColor = AppColors.primary

        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.widthAnchor.constraint(equalTo: button.heightAnchor).isActive = true

        button.addTarget(self, action: action, for: .touchUpInside)
        button.isEnabled = false
        button.alpha = 0.5

        return button
    }

    private lazy var emptyStateView: EmptyStateView = {
        let view = EmptyStateView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isHidden = true
        return view
    }()
    
    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        loadData()

        // Авто-оновлення UI, коли CoreData контекст змінюється
        contextObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            // щоб не влізти в активні апдейти/анімації collectionView
            DispatchQueue.main.async {
                self.loadData()
            }
        }
    }

    deinit {
        if let contextObserver { NotificationCenter.default.removeObserver(contextObserver) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadData()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let circularButtons: [UIButton] = [sortButton, shareActionButton, moveActionButton, deleteActionButton]
        circularButtons.forEach { btn in
            btn.layer.cornerRadius = btn.bounds.height / 2
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = AppColors.background

        view.addSubview(collectionView)
        view.addSubview(emptyStateView)
        
        // Додаємо всі кнопки в stack
        controlsStackView.addArrangedSubview(selectButton)
        controlsStackView.addArrangedSubview(UIView()) // spacer
        
        // Кнопки дій (сховані по дефолту)
        controlsStackView.addArrangedSubview(shareActionButton)
        controlsStackView.addArrangedSubview(moveActionButton)
        controlsStackView.addArrangedSubview(deleteActionButton)
        
        // Кнопка сортування (видима по дефолту)
        controlsStackView.addArrangedSubview(sortButton)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40)
        ])
    }

    private func setupNavigationBar() {
        title = "Scans"
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppColors.background
        appearance.titleTextAttributes = [
            .foregroundColor: AppColors.darkGray,
            .font: AppFonts.bold(24)
        ]

        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.navigationBar.isTranslucent = false
    }

    private func createLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewCompositionalLayout { [weak self] sectionIndex, environment in
            guard self != nil else { return nil }
            if sectionIndex == 0 {
                // Folders: horizontally scrolling tiles 240x80, height ~100
                let itemSize = NSCollectionLayoutSize(widthDimension: .absolute(240), heightDimension: .absolute(80))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)

                let groupSize = NSCollectionLayoutSize(widthDimension: .estimated(240), heightDimension: .absolute(100))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
                // group.interItemSpacing = .fixed(16)

                let section = NSCollectionLayoutSection(group: group)
                section.orthogonalScrollingBehavior = .continuous
                section.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16)
                section.interGroupSpacing = 12
                return section
            } else {
                // Documents: full-width rows, header with search + controls
                let itemSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .absolute(80))
                let item = NSCollectionLayoutItem(layoutSize: itemSize)

                let groupSize = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1.0), heightDimension: .estimated(80))
                let group = NSCollectionLayoutGroup.vertical(layoutSize: groupSize, subitems: [item])
                // group.interItemSpacing = .fixed(16)

                let section = NSCollectionLayoutSection(group: group)
                section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
                section.interGroupSpacing = 12

                section.supplementariesFollowContentInsets = false

                let headerSize = NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1.0),
                    heightDimension: .estimated(96)
                )
                
                let header = NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: headerSize,
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )
                header.pinToVisibleBounds = true
                header.zIndex = 2
                section.boundarySupplementaryItems = [header]
                return section
            }
        }
        return layout
    }

    // MARK: - Data (Core Data fetch)

    private func loadData() {
        folders = fetchFolders()
        documents = fetchDocuments(folderId: currentFolderId)
        applySavedSortAndReloadDocuments()

        let isEmpty = folders.isEmpty && documents.isEmpty
        emptyStateView.isHidden = !isEmpty
        collectionView.isHidden = isEmpty

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

    private func fetchDocuments(folderId: UUID?) -> [CDDocument] {
        let req: NSFetchRequest<CDDocument> = CDDocument.fetchRequest()

        if let folderId {
            req.predicate = NSPredicate(format: "folder.id == %@", folderId as CVarArg)
        } else {
            // "No Folder" — показуємо документи без папки
            req.predicate = NSPredicate(format: "folder == nil")
        }

        req.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return (try? context.fetch(req)) ?? []
    }
    
    // MARK: - Selection Mode Actions (тільки для документів)
    
    @objc private func selectButtonTapped() {
        isSelectionMode.toggle()
        
        if isSelectionMode {
            selectButton.setTitle("Cancel", for: .normal)
            selectButton.backgroundColor = AppColors.cellBackground
            selectButton.setTitleColor(.systemGray, for: .normal)
            selectButton.setTitleColor(.systemGray, for: .highlighted)

            // Сховати кнопку сортування
            sortButton.isHidden = true
            
            // Показати кнопки дій
            shareActionButton.isHidden = false
            moveActionButton.isHidden = false
            deleteActionButton.isHidden = false
            
            UIView.performWithoutAnimation {
                self.view.layoutIfNeeded()
                [self.sortButton, self.shareActionButton, self.moveActionButton, self.deleteActionButton].forEach { btn in
                    btn.layer.cornerRadius = btn.bounds.height / 2
                }
            }
            
        } else {
            selectButton.setTitle("Select", for: .normal)
            selectButton.backgroundColor = AppColors.primary
            selectButton.setTitleColor(.white, for: .normal)
            selectButton.setTitleColor(.white, for: .highlighted)
            
            selectedDocuments.removeAll()
            
            // Показати кнопку сортування
            sortButton.isHidden = false
            
            // Сховати кнопки дій
            shareActionButton.isHidden = true
            moveActionButton.isHidden = true
            deleteActionButton.isHidden = true
            
            UIView.performWithoutAnimation {
                self.view.layoutIfNeeded()
                [self.sortButton, self.shareActionButton, self.moveActionButton, self.deleteActionButton].forEach { btn in
                    btn.layer.cornerRadius = btn.bounds.height / 2
                }
            }
        }
        
        updateActionButtons()
        collectionView.reloadSections(IndexSet(integer: 0))
        collectionView.reloadSections(IndexSet(integer: 1))
    }
    
    @objc private func sortButtonTapped() {
        let alert = UIAlertController(title: "Sort by", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(
            title: sortTitle("Name (A-Z)", option: .nameAZ),
            style: .default
        ) { [weak self] _ in
            AppSettings.shared.documentsSortOption = .nameAZ
            self?.applySavedSortAndReloadDocuments()
        })

        alert.addAction(UIAlertAction(
            title: sortTitle("Name (Z-A)", option: .nameZA),
            style: .default
        ) { [weak self] _ in
            AppSettings.shared.documentsSortOption = .nameZA
            self?.applySavedSortAndReloadDocuments()
        })

        alert.addAction(UIAlertAction(
            title: sortTitle("Date (Newest)", option: .dateNewest),
            style: .default
        ) { [weak self] _ in
            AppSettings.shared.documentsSortOption = .dateNewest
            self?.applySavedSortAndReloadDocuments()
        })

        alert.addAction(UIAlertAction(
            title: sortTitle("Date (Oldest)", option: .dateOldest),
            style: .default
        ) { [weak self] _ in
            AppSettings.shared.documentsSortOption = .dateOldest
            self?.applySavedSortAndReloadDocuments()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.view.tintColor = AppColors.primary

        if let pop = alert.popoverPresentationController {
            pop.sourceView = sortButton
            pop.sourceRect = sortButton.bounds
        }
        present(alert, animated: true)
    }
    
    private func sortTitle(_ title: String, option: DocumentsSortOption) -> String {
        let current = AppSettings.shared.documentsSortOption
        return (current == option) ? "✓  \(title)" : title
    }

    private func applySavedSortAndReloadDocuments() {
        switch AppSettings.shared.documentsSortOption {
        case .nameAZ:
            sortDocuments(by: "name", ascending: true)
        case .nameZA:
            sortDocuments(by: "name", ascending: false)
        case .dateNewest:
            sortDocuments(by: "createdAt", ascending: false)
        case .dateOldest:
            sortDocuments(by: "createdAt", ascending: true)
        }
    }
    
    private func sortDocuments(by key: String, ascending: Bool) {
        documents.sort {
            guard let val1 = $0.value(forKey: key),
                  let val2 = $1.value(forKey: key) else { return false }

            if let str1 = val1 as? String, let str2 = val2 as? String {
                return ascending ? str1 < str2 : str1 > str2
            }
            if let date1 = val1 as? Date, let date2 = val2 as? Date {
                return ascending ? date1 < date2 : date1 > date2
            }
            return false
        }
    }
    
    @objc private func shareSelectedTapped() {
        guard !selectedDocuments.isEmpty else { return }

        requirePremium { [weak self] in
            guard let self else { return }

            var urls: [URL] = []
            for docId in self.selectedDocuments {
                if let doc = self.documents.first(where: { $0.id == docId }),
                   let fileName = doc.pdfFileName,
                   let url = self.pdfURL(fileName: fileName) {
                    urls.append(url)
                }
            }

            guard !urls.isEmpty else { return }
            let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            self.present(activityVC, animated: true)
        }
    }

    @objc private func moveSelectedTapped() {
        guard !selectedDocuments.isEmpty else { return }

        let current: CDFolder? = currentFolderId.flatMap { fetchFolder(by: $0) }

        let vc = MoveToFolderViewController(currentFolder: current, context: context)
        vc.onPick = { [weak self] targetFolder in
            self?.moveSelectedDocuments(to: targetFolder)
        }

        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }
    
    private func moveSelectedDocuments(to folder: CDFolder?) {
        // Update Core Data for selected docs and collect their IDs
        var movedIds: [UUID] = []
        for docId in selectedDocuments {
            if let doc = documents.first(where: { $0.id == docId }) {
                doc.folder = folder
                doc.updatedAt = Date()
                if let id = doc.id { movedIds.append(id) }
            }
        }
        CoreDataStack.shared.saveIfNeeded()

        // Determine which moved docs no longer belong to the current filter
        let indicesToRemove: [Int] = documents.enumerated().compactMap { (idx, doc) in
            guard let id = doc.id, movedIds.contains(id) else { return nil }
            let belongs: Bool
            if let currentFolderId = self.currentFolderId {
                belongs = (doc.folder?.id == currentFolderId)
            } else {
                belongs = (doc.folder == nil)
            }
            return belongs ? nil : idx
        }

        let indexPaths = indicesToRemove.map { IndexPath(item: $0, section: 1) }

        // Update local data source
        for i in indicesToRemove.sorted(by: >) {
            documents.remove(at: i)
        }

        selectedDocuments.removeAll()
        updateActionButtons()

        // Update UI
        if indexPaths.isEmpty {
            // Nothing to visually remove; just exit selection mode
            selectButtonTapped()
        } else {
            collectionView.performBatchUpdates({
                collectionView.deleteItems(at: indexPaths)
            }, completion: { [weak self] _ in
                guard let self else { return }
                let isEmpty = self.folders.isEmpty && self.documents.isEmpty
                self.emptyStateView.isHidden = !isEmpty
                self.collectionView.isHidden = isEmpty
                self.selectButtonTapped() // Exit selection mode after updates
            })
        }
    }
    
    @objc private func deleteSelectedTapped() {
        let count = selectedDocuments.count
        
        let alert = UIAlertController(
            title: "Delete Items",
            message: "Are you sure you want to delete \(count) item(s)?",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete()
        })
        
        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }
    
    private func performDelete() {
        // Determine which indices to delete in the current data source
        let indicesToDelete: [Int] = documents.enumerated().compactMap { (idx, doc) in
            guard let id = doc.id else { return nil }
            return selectedDocuments.contains(id) ? idx : nil
        }
        guard !indicesToDelete.isEmpty else { return }

        let indexPaths = indicesToDelete.map { IndexPath(item: $0, section: 1) }

        // Delete files and Core Data objects
        for i in indicesToDelete {
            let doc = documents[i]
            deletePDFFileIfNeeded(fileName: doc.pdfFileName)
            context.delete(doc)
        }
        CoreDataStack.shared.saveIfNeeded()

        // Update local data source
        for i in indicesToDelete.sorted(by: >) {
            documents.remove(at: i)
        }
        selectedDocuments.removeAll()
        updateActionButtons()

        // Update collection view immediately to prevent placeholder cells
        collectionView.performBatchUpdates({
            collectionView.deleteItems(at: indexPaths)
        }, completion: { [weak self] _ in
            guard let self else { return }
            let isEmpty = self.folders.isEmpty && self.documents.isEmpty
            self.emptyStateView.isHidden = !isEmpty
            self.collectionView.isHidden = isEmpty
            // Exit selection mode (updates header controls and reloads sections safely)
            self.selectButtonTapped()
        })
    }
    
    private func updateActionButtons() {
        let hasSelection = !selectedDocuments.isEmpty
        
        shareActionButton.isEnabled = hasSelection
        moveActionButton.isEnabled = hasSelection
        deleteActionButton.isEnabled = hasSelection
        
        shareActionButton.alpha = hasSelection ? 1.0 : 0.5
        moveActionButton.alpha = hasSelection ? 1.0 : 0.5
        deleteActionButton.alpha = hasSelection ? 1.0 : 0.5
    }

    // MARK: - Actions

    private func showCreateFolderAlert() {
        let alert = UIAlertController(title: "Enter name new folder", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Name" }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            guard let self else { return }
            guard let name = alert.textFields?.first?.text, !name.isEmpty else { return }
            self.createFolder(name: name)
        })

        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }

    private func createFolder(name: String) {
        let f = CDFolder(context: context)
        f.id = UUID()
        f.name = name
        f.createdAt = Date()
        CoreDataStack.shared.saveIfNeeded()
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }

    // MARK: - Import / Scan

    func openScanner() {
        guard VNDocumentCameraViewController.isSupported else {
            showAlert(title: "Not Supported", message: "Document scanning is not supported on this device.")
            return
        }
        let scannerVC = VNDocumentCameraViewController()
        scannerVC.delegate = self
        present(scannerVC, animated: true)
    }

    func openPhotoLibrary() {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 10
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func openWebPageConverter() {
        let webVC = WebPageConverterViewController()
        let navController = UINavigationController(rootViewController: webVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    func openDocumentPicker() {
        let supportedTypes: [UTType] = [.pdf, .image, .jpeg, .png]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showAlert(title: "Not Supported", message: "Camera is not available on this device.")
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = self
        present(picker, animated: true)
    }

    private func processImportedDocument(at url: URL) {
        let baseName = url.deletingPathExtension().lastPathComponent
        guard let pdfData = try? Data(contentsOf: url) else { return }
        persistPDF(data: pdfData, name: baseName, folderId: currentFolderId)
    }

    // MARK: - Persist PDF into CoreData + Filesystem

    private func persistPDF(data: Data, name: String, folderId: UUID?) {
        let fileName = "\(UUID().uuidString).pdf"
        guard let fileURL = pdfURL(fileName: fileName) else { return }

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("PDF write error:", error)
            return
        }

        let doc = CDDocument(context: context)
        doc.id = UUID()
        doc.name = name
        doc.createdAt = Date()
        doc.updatedAt = Date()
        doc.pdfFileName = fileName
        doc.sizeBytes = Int64(data.count)

        if let pdf = PDFDocument(data: data) {
            doc.pageCount = Int16(pdf.pageCount)
            if let thumb = makePDFThumbnail(pdf: pdf) {
                doc.thumbnailData = thumb.jpegData(compressionQuality: 0.85)
            }
        } else {
            doc.pageCount = 0
        }

        if let folderId, let folder = fetchFolder(by: folderId) {
            doc.folder = folder
        } else {
            doc.folder = nil
        }

        CoreDataStack.shared.saveIfNeeded()
    }

    private func fetchFolder(by id: UUID) -> CDFolder? {
        let req: NSFetchRequest<CDFolder> = CDFolder.fetchRequest()
        req.fetchLimit = 1
        req.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(req).first
    }

    private func pdfURL(fileName: String) -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    private func makePDFThumbnail(pdf: PDFDocument) -> UIImage? {
        guard let page = pdf.page(at: 0) else { return nil }
        let size = CGSize(width: 200, height: 200)
        return page.thumbnail(of: size, for: .mediaBox)
    }

    private func deletePDFFileIfNeeded(fileName: String?) {
        guard let fileName, let url = pdfURL(fileName: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - UICollectionViewDataSource

extension MainViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if section == 0 { return folders.count } else { return documents.count }
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == 0 {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: FolderCollectionCell.identifier,
                for: indexPath
            ) as! FolderCollectionCell
            cell.delegate = self
            let folder = folders[indexPath.item]
            let count = (folder.documents as? Set<CDDocument>)?.count ?? 0
            cell.configure(with: folder, documentCount: count)
            cell.setSelectionMode(isSelectionMode)
            cell.showSelectionIndicator(false)
            // Dim and disable folders when in selection mode
            cell.isUserInteractionEnabled = !isSelectionMode
            cell.alpha = isSelectionMode ? 0.5 : 1.0
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: DocumentCollectionCell.identifier,
                for: indexPath
            ) as! DocumentCollectionCell

            cell.delegate = self
            let doc = documents[indexPath.item]
            cell.configure(with: doc)
            cell.setSelectionMode(isSelectionMode)

            if isSelectionMode {
                cell.isSelected = selectedDocuments.contains(doc.id ?? UUID())
                cell.showSelectionIndicator(true)
            } else {
                cell.showSelectionIndicator(false)
            }
            return cell
        }
    }
    
    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        if kind == UICollectionView.elementKindSectionHeader && indexPath.section == 1 {
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: DocumentsHeaderView.reuseIdentifier,
                for: indexPath
            ) as! DocumentsHeaderView
            header.configure(searchView: searchView, controls: controlsStackView)
            return header
        }
        return UICollectionReusableView()
    }
}

// MARK: - UICollectionViewDelegate

extension MainViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            // Folders: open only when not in selection mode
            guard !isSelectionMode else { return }
            let folder = folders[indexPath.item]
            let vc = FolderViewController(folder: folder, context: context)
            navigationController?.pushViewController(vc, animated: true)
        } else {
            if isSelectionMode {
                let doc = documents[indexPath.item]
                if let id = doc.id {
                    if selectedDocuments.contains(id) { selectedDocuments.remove(id) } else { selectedDocuments.insert(id) }
                }
                updateActionButtons()
                collectionView.reloadItems(at: [indexPath])
            } else {
                let doc = documents[indexPath.item]
                openDocumentWithSubscriptionCheck(doc)
            }
        }
    }
}

// MARK: - UISearchBarDelegate

extension MainViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        currentSearchQuery = searchText
        if searchText.isEmpty {
            documents = fetchDocuments(folderId: currentFolderId)
            collectionView.reloadSections(IndexSet(integer: 1))
        }
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        let text = searchBar.text ?? ""
        currentSearchQuery = text
        
        if text.isEmpty {
            documents = fetchDocuments(folderId: currentFolderId)
        } else {
            let allDocs = fetchDocuments(folderId: currentFolderId)
            let searchLower = text.lowercased()
            documents = allDocs.filter { ($0.name?.lowercased().contains(searchLower) ?? false) }
        }

        applySavedSortAndReloadDocuments()
        collectionView.reloadSections(IndexSet(integer: 1))
        searchBar.resignFirstResponder()
    }
}

// MARK: - FolderCollectionCellDelegate

extension MainViewController: FolderCollectionCellDelegate {

    func folderCellDidTapMore(_ cell: FolderCollectionCell) {
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let folder = folders[indexPath.item]

        let alert = UIAlertController(title: folder.name, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.renameFolder(folder)
        })

        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.deleteFolder(folder)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.view.tintColor = AppColors.primary

        if let pop = alert.popoverPresentationController {
            pop.sourceView = cell.moreAnchorView
            pop.sourceRect = cell.moreAnchorView.bounds
            pop.permittedArrowDirections = [.up, .down]
        }

        present(alert, animated: true)
    }

    private func renameFolder(_ folder: CDFolder) {
        let alert = UIAlertController(title: "Rename Folder", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = folder.name }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            guard let newName = alert.textFields?.first?.text, !newName.isEmpty else { return }

            folder.name = newName
            CoreDataStack.shared.saveIfNeeded()

            self.folders = self.fetchFolders()
            self.collectionView.reloadSections(IndexSet(integer: 0))
        })

        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }

    private func deleteFolder(_ folder: CDFolder) {
        // 1) прибрати pdf файли (як у тебе)
        if let docs = folder.documents as? Set<CDDocument> {
            for d in docs { deletePDFFileIfNeeded(fileName: d.pdfFileName) }
        }

        // 2) видалити з CoreData
        context.delete(folder)
        CoreDataStack.shared.saveIfNeeded()

        // 3) оновити data source і UI одним кроком
        folders = fetchFolders()
        documents = fetchDocuments(folderId: currentFolderId)
        applySavedSortAndReloadDocuments()

        // без batch updates
        collectionView.reloadData()
    }
}

// MARK: - DocumentCollectionCellDelegate

extension MainViewController: DocumentCollectionCellDelegate {

    func documentCellDidTapMore(_ cell: DocumentCollectionCell) {
        guard !isSelectionMode else { return } // Не показувати меню в режимі вибору
        guard let indexPath = collectionView.indexPath(for: cell) else { return }
        let document = documents[indexPath.item]

        let alert = UIAlertController(title: document.name, message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "Share", style: .default) { [weak self] _ in
            self?.shareDocument(document)
        })

        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self] _ in
            self?.renameDocument(document)
        })

        alert.addAction(UIAlertAction(title: "Move", style: .default) { [weak self] _ in
            self?.moveDocumentToFolder(document)
        })

        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }

            // Resolve index in current data source
            let docId = document.id
            let index = docId.flatMap { id in
                self.documents.firstIndex(where: { $0.id == id })
            }

            // Delete file and Core Data object
            self.deletePDFFileIfNeeded(fileName: document.pdfFileName)
            self.context.delete(document)
            CoreDataStack.shared.saveIfNeeded()

            // If we can map to a visible index, update UI immediately
            if let idx = index {
                self.documents.remove(at: idx)
                let indexPath = IndexPath(item: idx, section: 1)
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [indexPath])
                }, completion: { _ in
                    let isEmpty = self.folders.isEmpty && self.documents.isEmpty
                    self.emptyStateView.isHidden = !isEmpty
                    self.collectionView.isHidden = isEmpty
                })
            }
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.view.tintColor = AppColors.primary

        if let pop = alert.popoverPresentationController {
            pop.sourceView = cell.moreAnchorView
            pop.sourceRect = cell.moreAnchorView.bounds
            pop.permittedArrowDirections = [.up, .down]
        }

        present(alert, animated: true)
    }

    private func shareDocument(_ document: CDDocument) {
        requirePremium { [weak self] in
            guard let self else { return }
            guard let fileName = document.pdfFileName,
                  let url = self.pdfURL(fileName: fileName) else { return }

            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            self.present(activityVC, animated: true)
        }
    }

    private func renameDocument(_ document: CDDocument) {
        let alert = UIAlertController(title: "Rename Document", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = document.name }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            guard let newName = alert.textFields?.first?.text, !newName.isEmpty else { return }
            document.name = newName
            document.updatedAt = Date()
            CoreDataStack.shared.saveIfNeeded()
        })
        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }

    // *** REPLACED METHOD IMPLEMENTATION ***
    private func moveDocumentToFolder(_ document: CDDocument) {
        let current: CDFolder? = currentFolderId.flatMap { fetchFolder(by: $0) }
        let picker = MoveToFolderViewController(currentFolder: current, context: context)
        picker.onPick = { [weak self] targetFolder in
            guard let self else { return }
            document.folder = targetFolder
            document.updatedAt = Date()
            CoreDataStack.shared.saveIfNeeded()
            self.removeIfMovedOut(document)
        }
        let nav = UINavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    private func deleteDocument(_ document: CDDocument) {
        let alert = UIAlertController(title: "Delete Document",
                                      message: "Are you sure you want to delete '\(document.name ?? "")'?",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }

            // Resolve index in current data source
            let docId = document.id
            let index = docId.flatMap { id in
                self.documents.firstIndex(where: { $0.id == id })
            }

            // Delete file and Core Data object
            self.deletePDFFileIfNeeded(fileName: document.pdfFileName)
            self.context.delete(document)
            CoreDataStack.shared.saveIfNeeded()

            // If we can map to a visible index, update UI immediately
            if let idx = index {
                self.documents.remove(at: idx)
                let indexPath = IndexPath(item: idx, section: 1)
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [indexPath])
                }, completion: { _ in
                    let isEmpty = self.folders.isEmpty && self.documents.isEmpty
                    self.emptyStateView.isHidden = !isEmpty
                    self.collectionView.isHidden = isEmpty
                })
            }
        })
        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }
    
    // *** NEW HELPER METHOD ***
    private func removeIfMovedOut(_ document: CDDocument) {
        let belongs: Bool
        if let currentFolderId = self.currentFolderId {
            belongs = (document.folder?.id == currentFolderId)
        } else {
            belongs = (document.folder == nil)
        }

        guard !belongs, let id = document.id,
              let idx = self.documents.firstIndex(where: { $0.id == id }) else { return }

        // Update local data source and UI
        self.documents.remove(at: idx)
        let indexPath = IndexPath(item: idx, section: 1)
        self.collectionView.performBatchUpdates({
            self.collectionView.deleteItems(at: [indexPath])
        }, completion: { [weak self] _ in
            guard let self else { return }
            let isEmpty = self.folders.isEmpty && self.documents.isEmpty
            self.emptyStateView.isHidden = !isEmpty
            self.collectionView.isHidden = isEmpty
        })
    }
}

// MARK: - VNDocumentCameraViewControllerDelegate

extension MainViewController: VNDocumentCameraViewControllerDelegate {

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFinishWith scan: VNDocumentCameraScan) {
        controller.dismiss(animated: true)

        var images: [UIImage] = []
        for i in 0..<scan.pageCount { images.append(scan.imageOfPage(at: i)) }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "Scan_\(df.string(from: Date()))"

        if let pdfData = makePDFDataFromImagesOriginalSize(images) {
            persistPDF(data: pdfData, name: name, folderId: currentFolderId)
        }
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        controller.dismiss(animated: true)
    }

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFailWithError error: Error) {
        controller.dismiss(animated: true)
        showAlert(title: "Scan Failed", message: error.localizedDescription)
    }

    // MARK: - PDF from Images (original page size)

    private func makePDFDocument(from images: [UIImage]) -> PDFDocument? {
        let pdf = PDFDocument()
        for (i, img) in images.enumerated() {
            guard let page = PDFPage(image: img) else { continue }
            pdf.insert(page, at: i)
        }
        return pdf.pageCount > 0 ? pdf : nil
    }

    private func makePDFDataFromImagesOriginalSize(_ images: [UIImage]) -> Data? {
        guard let pdf = makePDFDocument(from: images) else { return nil }
        return pdf.dataRepresentation()
    }

}

// MARK: - PHPickerViewControllerDelegate

extension MainViewController: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else { return }

        var images: [UIImage] = []
        let group = DispatchGroup()

        for result in results {
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { obj, _ in
                defer { group.leave() }
                if let img = obj as? UIImage { images.append(img) }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self, !images.isEmpty else { return }

            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let name = "Gallery_\(df.string(from: Date()))"

            if let pdfData = self.makePDFDataFromImagesOriginalSize(images) {
                self.persistPDF(data: pdfData, name: name, folderId: self.currentFolderId)
            }
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension MainViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {

        var images: [UIImage] = []
        var pdfs: [(Data, String)] = []

        for url in urls {
            let ext = url.pathExtension.lowercased()

            if ext == "pdf", let data = try? Data(contentsOf: url) {
                pdfs.append((data, url.deletingPathExtension().lastPathComponent))
            } else if let img = UIImage(contentsOfFile: url.path) {
                images.append(img)
            }
        }

        if !images.isEmpty, let pdfData = makePDFDataFromImagesOriginalSize(images) {            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let name = "Imported_\(df.string(from: Date()))"
            persistPDF(data: pdfData, name: name, folderId: currentFolderId)
        }

        for (data, name) in pdfs {
            persistPDF(data: data, name: name, folderId: currentFolderId)
        }
    }
}

// MARK: - UIImagePickerControllerDelegate

extension MainViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        let image = (info[.originalImage] as? UIImage)

        picker.dismiss(animated: true) { [weak self] in
            guard let self, let image else { return }
            self.presentCrop(for: image)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

extension MainViewController: CenterMenuActionHandling {
    func handleCenterMenuAction(_ action: CenterMenuActionType) {
        switch action {
        case .scan:      openScanner()
        case .camera:    openCamera()
        case .gallery:   openPhotoLibrary()
        case .folder:    showCreateFolderAlert()
        case .webPage:   openWebPageConverter()
        case .documents: openDocumentPicker()
        }
    }
}

extension MainViewController {
    
    private func openDocumentWithSubscriptionCheck(_ doc: CDDocument) {
        requirePremium { [weak self] in
            self?.pushDocument(doc)
        }
    }

    @MainActor
    private func pushDocument(_ doc: CDDocument) {
        let vc = DocumentDetailViewController(document: doc, context: context)
        navigationController?.pushViewController(vc, animated: true)
    }

    private func requirePremium(
        placementID: String = AppConfig.Adapty.paywallActionPlacementID,
        onGranted: @escaping @MainActor () -> Void
    ) {
        view.isUserInteractionEnabled = false

        Task { @MainActor in
            await SubscriptionManager.shared.updatePremiumStatus()

            if SubscriptionManager.shared.isPremiumActive {
                self.view.isUserInteractionEnabled = true
                onGranted()
                return
            }

            // важливо: якщо вже щось показано — не лочимо UI назавжди
            guard self.presentedViewController == nil else {
                self.view.isUserInteractionEnabled = true
                return
            }

            SubscriptionManager.shared.presentPaywallWithFallback(
                placementID: placementID,
                from: self,
                animated: true
            ) { [weak self] result in
                guard let self else { return }
                self.view.isUserInteractionEnabled = true

                switch result {
                case .purchased, .restored:
                    Task { @MainActor in
                        await SubscriptionManager.shared.updatePremiumStatus()
                        if SubscriptionManager.shared.isPremiumActive {
                            onGranted()
                        }
                    }
                case .dismissed, .skipped, .loadingError, .purchaseError:
                    break
                }
            }
        }
    }
}

// MARK: - Crop (Camera -> Crop -> PDF)
extension MainViewController: CropViewControllerDelegate {

    private func presentCrop(for image: UIImage) {
        // (Опційно) нормалізуємо орієнтацію, щоб не було “перевернутих” кропів
        let normalized = image.normalizedImage()

        let cropVC = CropViewController(image: normalized)
        cropVC.delegate = self

        cropVC.aspectRatioPreset = normalized.size
        cropVC.resetAspectRatioEnabled = true
        cropVC.aspectRatioLockEnabled = false
        cropVC.rotateButtonsHidden = false
        cropVC.rotateClockwiseButtonHidden = false

        cropVC.doneButtonTitle = "Save"
        cropVC.cancelButtonTitle = "Cancel"

        present(cropVC, animated: true)
    }

    func cropViewController(_ cropViewController: CropViewController,
                            didCropToImage image: UIImage,
                            withRect cropRect: CGRect,
                            angle: Int) {

        cropViewController.dismiss(animated: true) { [weak self] in
            guard let self else { return }

            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let name = "Camera_\(df.string(from: Date()))"

            // Зберігаємо як PDF (як у тебе було)
            if let pdfData = self.makePDFDataFromImagesOriginalSize([image]) {
                self.persistPDF(data: pdfData, name: name, folderId: self.currentFolderId)
            }
        }
    }

    func cropViewControllerDidCancel(_ cropViewController: CropViewController) {
        cropViewController.dismiss(animated: true, completion: nil)
    }
}
