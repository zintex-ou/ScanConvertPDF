//
//  FolderViewController.swift
//  ScanConvertPDF
//

import UIKit
import VisionKit
import PhotosUI
import CropViewController
import UniformTypeIdentifiers
import CoreData
import PDFKit

final class FolderViewController: UIViewController {

    private enum FolderAddAction {
        case scan
        case camera
        case gallery
        case webPage
        case documents
    }

    // MARK: - Add Menu
    private let addMenu = CenterButtonMenu()
    private var isAddMenuOpen = false

    // MARK: - Core Data
    private let context: NSManagedObjectContext
    private let folder: CDFolder

    // MARK: - Data
    private var allDocuments: [CDDocument] = []
    private var documents: [CDDocument] = []

    // MARK: - Selection Mode
    private var isSelectionMode = false
    private var selectedDocuments: Set<UUID> = []

    // MARK: - Search
    private var currentSearchQuery: String = ""

    // MARK: - UI
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 100, right: 16)
        layout.sectionHeadersPinToVisibleBounds = true

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.delegate = self
        cv.dataSource = self
        cv.register(DocumentCollectionCell.self, forCellWithReuseIdentifier: DocumentCollectionCell.identifier)
        cv.register(DocumentsHeaderView.self,
                    forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                    withReuseIdentifier: DocumentsHeaderView.reuseIdentifier)

        cv.contentInsetAdjustmentBehavior = .always
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.alwaysBounceVertical = true
        cv.keyboardDismissMode = .onDrag

        return cv
    }()

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "No documents in this folder"
        label.font = AppFonts.regular(16)
        label.textColor = AppColors.textSecondary
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    private lazy var addButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .bold)
        button.setImage(UIImage(systemName: "plus", withConfiguration: config), for: .normal)

        button.tintColor = .white
        button.backgroundColor = AppColors.primary
        button.layer.cornerRadius = 28
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 6)
        button.layer.shadowRadius = 14
        button.layer.shadowOpacity = 0.18

        button.addTarget(self, action: #selector(addButtonTapped), for: .touchUpInside)
        return button
    }()

    // MARK: - Header UI (Search + Select + Actions + Sort)

    private lazy var searchView: SearchFieldView = {
        let v = SearchFieldView()
        v.translatesAutoresizingMaskIntoConstraints = false

        v.onTextChanged = { [weak self] text in
            guard let self else { return }
            self.currentSearchQuery = text
            if text.isEmpty {
                self.documents = self.allDocuments
                self.syncSelectionWithVisibleDocuments()
                self.refreshEmptyState()
                self.collectionView.reloadData()
            }
        }

        v.onSearchTapped = { [weak self] text in
            guard let self else { return }
            self.currentSearchQuery = text
            self.applySearchAndReload()
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

    private lazy var shareActionButton: UIButton = {
        let button = createActionButton(icon: "square.and.arrow.up", action: #selector(shareSelectedTapped))
        button.isHidden = true
        return button
    }()

    private lazy var moveActionButton: UIButton = {
        let button = createActionButton(icon: "folder", action: #selector(moveSelectedTapped))
        button.isHidden = true
        return button
    }()

    private lazy var deleteActionButton: UIButton = {
        let button = createActionButton(icon: "trash", action: #selector(deleteSelectedTapped))
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

    private var contextObserver: NSObjectProtocol?

    // MARK: - Init

    init(folder: CDFolder, context: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.folder = folder
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
        setupNavigationBar()
        setupAddMenu()
        setupHeaderControls()
        loadData()

        // авто-оновлення коли змінюються документи в цій папці
        contextObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.loadData()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rootTabBarController?.setTabBar(hidden: true, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isAddMenuOpen {
            addMenu.dismiss(animated: false)
            isAddMenuOpen = false
            setAddButton(isClose: false, animated: false)
        }
        rootTabBarController?.setTabBar(hidden: false, animated: true)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        [sortButton, shareActionButton, moveActionButton, deleteActionButton].forEach { btn in
            btn.layer.cornerRadius = btn.bounds.height / 2
        }
    }

    deinit {
        if let contextObserver { NotificationCenter.default.removeObserver(contextObserver) }
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = AppColors.background

        view.addSubview(collectionView)
        view.addSubview(addButton)

        // Empty state як backgroundView колекції (header не зникне ніколи)
        collectionView.backgroundView = emptyStateLabel

        NSLayoutConstraint.activate([
            // Collection
            collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Add Button
            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            addButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            addButton.widthAnchor.constraint(equalToConstant: 56),
            addButton.heightAnchor.constraint(equalToConstant: 56)
        ])
    }

    // MARK: - Navigation Bar

    private func setupNavigationBar() {
        title = folder.name ?? "Folder"
        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never

        // щоб контент не "пірнав" під navbar
        navigationController?.navigationBar.isTranslucent = false

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = AppColors.background
        appearance.shadowColor = .clear

        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance

        // Right bar button (Rename)
        let renameButton = UIBarButtonItem(
            image: UIImage(systemName: "pencil"),
            style: .plain,
            target: self,
            action: #selector(renameTapped)
        )
        // Removed tintColor line here as per instructions
        navigationItem.rightBarButtonItem = renameButton
    }

    @objc private func renameTapped() {
        // якщо відкритий add menu — закриємо
        if isAddMenuOpen {
            addMenu.dismiss(animated: false)
            isAddMenuOpen = false
            setAddButton(isClose: false, animated: false)
        }

        // якщо selection mode — вимкнемо, щоб не було конфліктів UX
        if isSelectionMode {
            selectButtonTapped()
        }

        let alert = UIAlertController(title: "Rename Folder", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            tf.placeholder = "Name"
            tf.text = self?.folder.name
            tf.clearButtonMode = .whileEditing
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            let newName = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !newName.isEmpty else { return }

            self.folder.name = newName
            CoreDataStack.shared.saveIfNeeded(in: context)
            self.title = newName
        })

        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }

    private func setupHeaderControls() {
        controlsStackView.addArrangedSubview(selectButton)
        controlsStackView.addArrangedSubview(UIView()) // spacer
        controlsStackView.addArrangedSubview(shareActionButton)
        controlsStackView.addArrangedSubview(moveActionButton)
        controlsStackView.addArrangedSubview(deleteActionButton)
        controlsStackView.addArrangedSubview(sortButton)
    }

    private func setupAddMenu() {
        addMenu.accentColor = AppColors.menuAccent
        addMenu.buttonBackgroundColor = AppColors.cellBackgroundHighlighted
        addMenu.overlayColor = UIColor.black.withAlphaComponent(0.4)

        addMenu.configure(actions: [
            CenterMenuAction(title: "Scan", systemIcon: "doc.viewfinder") { [weak self] in
                self?.handleAddAction(.scan)
            },
            CenterMenuAction(title: "Crop", systemIcon: "camera") { [weak self] in
                self?.handleAddAction(.camera)
            },
            CenterMenuAction(title: "Gallery", systemIcon: "photo.on.rectangle") { [weak self] in
                self?.handleAddAction(.gallery)
            },
            CenterMenuAction(title: "Web Page", systemIcon: "globe") { [weak self] in
                self?.handleAddAction(.webPage)
            },
            CenterMenuAction(title: "Documents", systemIcon: "doc.on.doc") { [weak self] in
                self?.handleAddAction(.documents)
            }
        ])

        addMenu.onDismiss = { [weak self] in
            self?.isAddMenuOpen = false
            self?.setAddButton(isClose: false, animated: true)
        }
    }

    // MARK: - Data

    private func loadData() {
        allDocuments = fetchDocuments(in: folder)
        applySearchAndReload()
    }
    
    private func applySavedSortAndReload() {
        // сортуємо саме "documents" (вже після пошуку/фільтра)
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

    private func applySearchAndReload() {
        let q = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            documents = allDocuments
        } else {
            documents = allDocuments.filter { ($0.name?.lowercased().contains(q) ?? false) }
        }

        applySavedSortAndReload()

        syncSelectionWithVisibleDocuments()
        refreshEmptyState()
        collectionView.reloadData()
    }

    private func refreshEmptyState() {
        collectionView.isHidden = false

        if documents.isEmpty {
            let q = currentSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            emptyStateLabel.text = q.isEmpty
                ? "No documents in this folder"
                : "No results for \"\(q)\""
            emptyStateLabel.isHidden = false
        } else {
            emptyStateLabel.isHidden = true
        }
    }

    private func syncSelectionWithVisibleDocuments() {
        // Якщо стоїмо в selection mode і юзер відфільтрував список —
        // прибираємо з selected те, що не видно (щоб кнопки дій були консистентні).
        guard isSelectionMode else { return }
        selectedDocuments = selectedDocuments.filter { id in
            documents.contains(where: { $0.id == id })
        }
        updateActionButtons()
    }

    private func fetchDocuments(in folder: CDFolder) -> [CDDocument] {
        let req: NSFetchRequest<CDDocument> = CDDocument.fetchRequest()
        req.predicate = NSPredicate(format: "folder == %@", folder)
        req.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return (try? context.fetch(req)) ?? []
    }

    private func fetchFolders() -> [CDFolder] {
        let req: NSFetchRequest<CDFolder> = CDFolder.fetchRequest()
        req.sortDescriptors = [
            NSSortDescriptor(key: "createdAt", ascending: false),
            NSSortDescriptor(key: "name", ascending: true)
        ]
        return (try? context.fetch(req)) ?? []
    }

    private func openScanner() {
        guard VNDocumentCameraViewController.isSupported else {
            showAlert(title: "Not Supported", message: "Document scanning is not supported on this device.")
            return
        }

        let scannerVC = VNDocumentCameraViewController()
        scannerVC.delegate = self
        present(scannerVC, animated: true)
    }
    
    private func openCamera() {
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

    private func openPhotoLibrary() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 20
        config.filter = .images

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private func openDocumentPicker() {
        // імпорт PDF або Images
        let supportedTypes: [UTType] = [.pdf, .image, .jpeg, .png]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }

    // MARK: - Persist

    private func persistPDF(data: Data, name: String) {
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
        doc.folder = folder

        if let pdf = PDFDocument(data: data) {
            doc.pageCount = Int16(pdf.pageCount)
            if let thumb = makePDFThumbnail(pdf: pdf) {
                doc.thumbnailData = thumb.jpegData(compressionQuality: 0.85)
            }
        } else {
            doc.pageCount = 0
        }

        CoreDataStack.shared.saveIfNeeded()
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

    private func makePDFData(from images: [UIImage]) -> Data? {
        guard !images.isEmpty else { return nil }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)) // A4-ish
        return renderer.pdfData { ctx in
            for img in images {
                ctx.beginPage()
                let pageBounds = ctx.pdfContextBounds

                let aspect = min(pageBounds.width / img.size.width,
                                 pageBounds.height / img.size.height)
                let size = CGSize(width: img.size.width * aspect,
                                  height: img.size.height * aspect)

                let origin = CGPoint(x: (pageBounds.width - size.width) / 2,
                                     y: (pageBounds.height - size.height) / 2)
                img.draw(in: CGRect(origin: origin, size: size))
            }
        }
    }

    private func deletePDFFileIfNeeded(fileName: String?) {
        guard let fileName, let url = pdfURL(fileName: fileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - UICollectionViewDataSource

extension FolderViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int { 1 }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        documents.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: DocumentCollectionCell.identifier,
            for: indexPath
        ) as! DocumentCollectionCell

        let doc = documents[indexPath.item]

        // In folder screen you had no "more" delegate; keep nil to avoid conflicts.
        cell.delegate = self
        cell.configure(with: doc)
        cell.setSelectionMode(isSelectionMode)

        if isSelectionMode {
            let id = doc.id ?? UUID()
            cell.isSelected = selectedDocuments.contains(id)
            cell.showSelectionIndicator(true)
        } else {
            cell.showSelectionIndicator(false)
        }

        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else { return UICollectionReusableView() }

        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: DocumentsHeaderView.reuseIdentifier,
            for: indexPath
        ) as! DocumentsHeaderView

        header.configure(searchView: searchView, controls: controlsStackView)
        return header
    }
}

// MARK: - UICollectionViewDelegate

extension FolderViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

        let doc = documents[indexPath.item]

        if isSelectionMode {
            if let id = doc.id {
                if selectedDocuments.contains(id) { selectedDocuments.remove(id) }
                else { selectedDocuments.insert(id) }
            }
            updateActionButtons()
            collectionView.reloadItems(at: [indexPath])
        } else {
            let doc = documents[indexPath.item]
            openDocumentWithSubscriptionCheck(doc)
        }
    }
}

// MARK: - UICollectionViewDelegateFlowLayout

extension FolderViewController: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        CGSize(width: collectionView.bounds.width - 32, height: 80)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        CGSize(width: collectionView.bounds.width, height: 106)
    }
}

// MARK: - VNDocumentCameraViewControllerDelegate

extension FolderViewController: VNDocumentCameraViewControllerDelegate {

    func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                      didFinishWith scan: VNDocumentCameraScan) {
        controller.dismiss(animated: true)

        var images: [UIImage] = []
        for i in 0..<scan.pageCount {
            images.append(scan.imageOfPage(at: i))
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "Scan_\(df.string(from: Date()))"

        if let pdfData = makePDFData(from: images) {
            persistPDF(data: pdfData, name: name)
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
}

// MARK: - PHPickerViewControllerDelegate

extension FolderViewController: PHPickerViewControllerDelegate {

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

            if let pdfData = self.makePDFData(from: images) {
                self.persistPDF(data: pdfData, name: name)
            }
        }
    }
}

// MARK: - UIDocumentPickerDelegate

extension FolderViewController: UIDocumentPickerDelegate {

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            let baseName = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension.lowercased()

            if ext == "pdf" {
                guard let data = try? Data(contentsOf: url) else { continue }
                persistPDF(data: data, name: baseName)
            } else {
                // image -> pdf
                if let img = UIImage(contentsOfFile: url.path),
                   let pdfData = makePDFData(from: [img]) {
                    persistPDF(data: pdfData, name: baseName)
                }
            }
        }
    }
}

// MARK: - Menu Actions (Add button + Center menu)

extension FolderViewController {

    @objc private func addButtonTapped() {
        if isAddMenuOpen {
            addMenu.dismiss()
        } else {
            isAddMenuOpen = true
            setAddButton(isClose: true, animated: true)
            addMenu.show(in: view, above: addButton, animated: true)
        }
    }

    private func setAddButton(isClose: Bool, animated: Bool) {
        let rotation: CGFloat = isClose ? .pi / 4 : 0

        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) { [weak self] in
                self?.addButton.transform = CGAffineTransform(rotationAngle: rotation)
            }
        } else {
            addButton.transform = CGAffineTransform(rotationAngle: rotation)
        }
    }

    private func handleAddAction(_ action: FolderAddAction) {
        // Не змішуємо "add menu" і selection mode
        if isSelectionMode {
            selectButtonTapped()
        }

        switch action {
        case .scan:
            openScanner()

        case .camera:
            openCamera()

        case .gallery:
            openPhotoLibrary()

        case .webPage:
            openWebPageConverter()

        case .documents:
            openDocumentPicker()
        }
    }

    func openWebPageConverter() {
        let webVC = WebPageConverterViewController()
        webVC.targetFolder = folder
        let navController = UINavigationController(rootViewController: webVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }
}

// MARK: - Header Actions (Select / Sort / Share / Move / Delete)

extension FolderViewController {

    @objc private func selectButtonTapped() {
        // закрити add menu якщо відкрите
        if isAddMenuOpen {
            addMenu.dismiss(animated: false)
            isAddMenuOpen = false
            setAddButton(isClose: false, animated: false)
        }

        isSelectionMode.toggle()

        if isSelectionMode {
            selectButton.setTitle("Cancel", for: .normal)
            selectButton.backgroundColor = AppColors.cellBackground
            selectButton.setTitleColor(.systemGray, for: .normal)
            selectButton.setTitleColor(.systemGray, for: .highlighted)

            sortButton.isHidden = true
            shareActionButton.isHidden = false
            moveActionButton.isHidden = false
            deleteActionButton.isHidden = false
        } else {
            selectButton.setTitle("Select", for: .normal)
            selectButton.backgroundColor = AppColors.primary
            selectButton.setTitleColor(.white, for: .normal)
            selectButton.setTitleColor(.white, for: .highlighted)

            selectedDocuments.removeAll()

            sortButton.isHidden = false
            shareActionButton.isHidden = true
            moveActionButton.isHidden = true
            deleteActionButton.isHidden = true
        }

        updateActionButtons()
        collectionView.reloadData()
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

    @objc private func sortButtonTapped() {
        let alert = UIAlertController(title: "Sort by", message: nil, preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(
            title: sortTitle("Name (A-Z)", option: .nameAZ),
            style: .default
        ) { [weak self] _ in
            AppSettings.shared.documentsSortOption = .nameAZ
            self?.applySavedSortAndReload()
        })

        alert.addAction(UIAlertAction(
            title: sortTitle("Name (Z-A)", option: .nameZA),
            style: .default
        ) { [weak self] _ in
            AppSettings.shared.documentsSortOption = .nameZA
            self?.applySavedSortAndReload()
        })

        alert.addAction(UIAlertAction(
            title: sortTitle("Date (Newest)", option: .dateNewest),
            style: .default
        ) { [weak self] _ in
            AppSettings.shared.documentsSortOption = .dateNewest
            self?.applySavedSortAndReload()
        })

        alert.addAction(UIAlertAction(
            title: sortTitle("Date (Oldest)", option: .dateOldest),
            style: .default
        ) { [weak self] _ in
            AppSettings.shared.documentsSortOption = .dateOldest
            self?.applySavedSortAndReload()
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
    
    private func sortDocuments(by key: String, ascending: Bool) {
        documents.sort {
            guard let v1 = $0.value(forKey: key), let v2 = $1.value(forKey: key) else { return false }
            if let s1 = v1 as? String, let s2 = v2 as? String { return ascending ? s1 < s2 : s1 > s2 }
            if let d1 = v1 as? Date, let d2 = v2 as? Date { return ascending ? d1 < d2 : d1 > d2 }
            return false
        }
    }

    @objc private func shareSelectedTapped() {
        guard !selectedDocuments.isEmpty else { return }

        requirePremium { [weak self] in
            guard let self else { return }

            let urls: [URL] = self.selectedDocuments.compactMap { id in
                guard let doc = self.documents.first(where: { $0.id == id }),
                      let fileName = doc.pdfFileName,
                      let url = self.pdfURL(fileName: fileName) else { return nil }
                return url
            }

            guard !urls.isEmpty else { return }
            let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            self.present(activityVC, animated: true)
        }
    }

    @objc private func moveSelectedTapped() {
        guard !selectedDocuments.isEmpty else { return }

        let vc = MoveToFolderViewController(currentFolder: folder, context: context)
        vc.onPick = { [weak self] targetFolder in
            self?.moveSelectedDocuments(to: targetFolder)
        }
        present(UINavigationController(rootViewController: vc), animated: true)
    }

    private func moveSelectedDocuments(to folder: CDFolder?) {
        // Update Core Data for selected docs and collect their IDs
        var movedIds: [UUID] = []
        for id in selectedDocuments {
            if let doc = documents.first(where: { $0.id == id }) {
                doc.folder = folder
                doc.updatedAt = Date()
                if let id = doc.id { movedIds.append(id) }
            }
        }
        CoreDataStack.shared.saveIfNeeded()

        // Determine which moved docs no longer belong to this folder
        let indicesToRemove: [Int] = documents.enumerated().compactMap { (idx, doc) in
            guard let id = doc.id, movedIds.contains(id) else { return nil }
            let belongs = (doc.folder == self.folder)
            return belongs ? nil : idx
        }

        let indexPaths = indicesToRemove.map { IndexPath(item: $0, section: 0) }

        // Update local data sources
        let idsToRemove = Set(indicesToRemove.compactMap { documents[$0].id })
        for i in indicesToRemove.sorted(by: >) {
            documents.remove(at: i)
        }
        allDocuments.removeAll { doc in
            guard let id = doc.id else { return false }
            return idsToRemove.contains(id)
        }

        // Clear selection and update action buttons
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
                self.refreshEmptyState()
                self.selectButtonTapped() // Exit selection mode after UI updates
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
        // Determine which indices to delete in the currently visible (filtered) documents
        let indicesToDelete: [Int] = documents.enumerated().compactMap { (idx, doc) in
            guard let id = doc.id else { return nil }
            return selectedDocuments.contains(id) ? idx : nil
        }
        guard !indicesToDelete.isEmpty else { return }

        let indexPaths = indicesToDelete.map { IndexPath(item: $0, section: 0) }

        // Delete files and Core Data objects
        for i in indicesToDelete {
            let doc = documents[i]
            deletePDFFileIfNeeded(fileName: doc.pdfFileName)
            context.delete(doc)
        }
        CoreDataStack.shared.saveIfNeeded()

        // Update local data sources: remove from documents and allDocuments
        let idsToDelete: Set<UUID> = Set(indicesToDelete.compactMap { documents[$0].id })

        for i in indicesToDelete.sorted(by: >) {
            documents.remove(at: i)
        }
        allDocuments.removeAll { doc in
            guard let id = doc.id else { return false }
            return idsToDelete.contains(id)
        }

        // Clear selection and update action buttons
        selectedDocuments.removeAll()
        updateActionButtons()

        // Update collection view immediately to prevent placeholder cells
        collectionView.performBatchUpdates({
            collectionView.deleteItems(at: indexPaths)
        }, completion: { [weak self] _ in
            guard let self else { return }
            self.refreshEmptyState()
            // Exit selection mode after UI updates complete
            if self.isSelectionMode {
                self.selectButtonTapped()
            }
        })
    }
}

// MARK: - DocumentCollectionCellDelegate
extension FolderViewController: DocumentCollectionCellDelegate {

    func documentCellDidTapMore(_ cell: DocumentCollectionCell) {
        guard !isSelectionMode else { return }
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
            self?.deleteDocument(document)
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
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            guard let newName = alert.textFields?.first?.text, !newName.isEmpty else { return }
            document.name = newName
            document.updatedAt = Date()
            CoreDataStack.shared.saveIfNeeded()
        })
        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }

    private func moveDocumentToFolder(_ document: CDDocument) {
        let picker = MoveToFolderViewController(currentFolder: folder, context: context)
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

    private func removeIfMovedOut(_ document: CDDocument) {
        // If the document no longer belongs to this folder, remove it from the list
        if document.folder != self.folder, let id = document.id,
           let idx = self.documents.firstIndex(where: { $0.id == id }) {
            // Update arrays
            self.documents.remove(at: idx)
            self.allDocuments.removeAll { $0.id == id }
            let indexPath = IndexPath(item: idx, section: 0)
            self.collectionView.performBatchUpdates({
                self.collectionView.deleteItems(at: [indexPath])
            }, completion: { [weak self] _ in
                self?.refreshEmptyState()
            })
        }
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
                let id = self.documents[idx].id
                self.documents.remove(at: idx)
                if let id { self.allDocuments.removeAll { $0.id == id } }
                let indexPath = IndexPath(item: idx, section: 0)
                self.collectionView.performBatchUpdates({
                    self.collectionView.deleteItems(at: [indexPath])
                }, completion: { _ in
                    self.refreshEmptyState()
                })
            }
        })
        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }
}

extension FolderViewController {

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

// MARK: - UIImagePickerControllerDelegate
extension FolderViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        let image = info[.originalImage] as? UIImage

        picker.dismiss(animated: true) { [weak self] in
            guard let self, let image else { return }
            self.presentCrop(for: image)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - Crop (Camera -> Crop -> PDF)
extension FolderViewController: CropViewControllerDelegate {

    private func presentCrop(for image: UIImage) {
        let normalized = image.normalizedImage()

        let cropVC = CropViewController(image: normalized)
        cropVC.delegate = self

        // У твоїй версії це CGSize, тому "original" = ratio картинки
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

            // FolderVC вже має makePDFData(from:) + persistPDF(data:name:)
            if let pdfData = self.makePDFData(from: [image]) {
                self.persistPDF(data: pdfData, name: name)
            }
        }
    }

    func cropViewControllerDidCancel(_ cropViewController: CropViewController) {
        cropViewController.dismiss(animated: true)
    }
}
