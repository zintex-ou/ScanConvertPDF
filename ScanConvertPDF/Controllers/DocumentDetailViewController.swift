//
//  DocumentDetailViewController.swift
//  ScanConvertPDF
//
//  Created by Developer
//

import UIKit
import PDFKit
import CoreData

final class DocumentDetailViewController: UIViewController {

    // MARK: - Properties

    private let document: CDDocument
    private let context: NSManagedObjectContext
    private var pdfDocument: PDFDocument?

    // MARK: - UI Elements

    private lazy var pageInfoLabel: PaddingLabel = {
        let label = PaddingLabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppFonts.medium(12)
        label.textColor = AppColors.textSecondary
        label.textAlignment = .center

        // pill
        label.backgroundColor = AppColors.cellBackground
        label.layer.cornerRadius = 12
        label.layer.masksToBounds = true
        label.contentInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        return label
    }()

    private lazy var pdfView: PDFView = {
        let view = PDFView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = AppColors.background
        return view
    }()

    /// Bottom bar "like tab bar" (no center button)
    private lazy var bottomBar: ActionDockBar = {
        let bar = ActionDockBar()
        bar.translatesAutoresizingMaskIntoConstraints = false

        bar.accentColor = AppColors.primary
        bar.unselectedColor = AppColors.primary
        bar.tabbarColor = AppColors.cellBackground

        bar.onTapShare = { [weak self] in self?.shareTapped() }
        bar.onTapOrganize = { [weak self] in self?.organizeTapped() }
        bar.onTapPrint = { [weak self] in self?.printTapped() }
        bar.onTapDelete = { [weak self] in self?.deleteTapped() }
        return bar
    }()

    // MARK: - Init

    init(document: CDDocument, context: NSManagedObjectContext = CoreDataStack.shared.context) {
        self.document = document
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
        loadPDF()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rootTabBarController?.setTabBar(hidden: true, animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        rootTabBarController?.setTabBar(hidden: false, animated: true)
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = AppColors.background

        view.addSubview(pdfView)
        view.addSubview(bottomBar)
        view.addSubview(pageInfoLabel)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 92),

            // Page pill під NavBar (поверх pdfView)
            pageInfoLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            pageInfoLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageInfoLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 24),
            pageInfoLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 90)
        ])

        // щоб pill не перекривав взаємодію з PDF (по бажанню можна лишити)
        pageInfoLabel.isUserInteractionEnabled = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pageChanged),
            name: .PDFViewPageChanged,
            object: pdfView
        )
    }

    private func setupNavigationBar() {
        title = document.name ?? "Document"

        navigationController?.navigationBar.prefersLargeTitles = false
        navigationItem.largeTitleDisplayMode = .never

        let renameButton = UIBarButtonItem(
            image: UIImage(systemName: "pencil"),
            style: .plain,
            target: self,
            action: #selector(renameTapped)
        )
        renameButton.tintColor = AppColors.primary
        navigationItem.rightBarButtonItem = renameButton
    }

    // MARK: - PDF Loading

    private func loadPDF() {
        guard let url = pdfURL() else {
            print("❌ DocumentDetail: pdfURL() == nil. pdfFileName:", document.pdfFileName ?? "nil")
            showAlert(title: "Error", message: "PDF file name is missing.")
            return
        }

        let exists = FileManager.default.fileExists(atPath: url.path)
        guard exists else {
            showAlert(title: "File Missing", message: "PDF file not found on device.")
            return
        }

        if let pdf = PDFDocument(url: url) {
            self.pdfDocument = pdf
            pdfView.document = pdf
            updatePageInfo()
        } else {
            showAlert(title: "Error", message: "Failed to open PDF (corrupted or unsupported).")
        }
    }

    private func pdfURL() -> URL? {
        guard let fileName = document.pdfFileName, !fileName.isEmpty else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(fileName)
    }

    // MARK: - Page Info

    @objc private func pageChanged() {
        updatePageInfo()
    }

    private func updatePageInfo() {
        guard let pdfDocument,
              let currentPage = pdfView.currentPage else { return }

        let index = pdfDocument.index(for: currentPage) + 1
        let total = pdfDocument.pageCount
        pageInfoLabel.text = "Page \(index) of \(total)"
        // якщо хочеш ховати при 1 сторінці:
        // pageInfoLabel.isHidden = (total <= 1)
    }

    // MARK: - Actions

    @objc private func renameTapped() {
        let alert = UIAlertController(title: "Rename Document", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] tf in
            tf.text = self?.document.name
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self else { return }
            guard let newName = alert.textFields?.first?.text, !newName.isEmpty else { return }

            self.document.name = newName
            self.document.updatedAt = Date()
            CoreDataStack.shared.saveIfNeeded()
            self.title = newName
        })

        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }

    private func organizeTapped() {
        guard let pdfDocument else { return }
        let reorderVC = ReorderPagesViewController(pdfDocument: pdfDocument) { [weak self] newDocument in
            self?.applyReorderedDocument(newDocument)
        }
        let nav = UINavigationController(rootViewController: reorderVC)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
    }

    private func applyReorderedDocument(_ newDocument: PDFDocument) {
        guard let url = pdfURL() else { return }
        guard newDocument.write(to: url) else {
            showAlert(title: "Error", message: "Failed to save page changes.")
            return
        }

        self.pdfDocument = newDocument
        pdfView.document = newDocument
        updatePageInfo()

        document.pageCount = Int16(newDocument.pageCount)
        if let firstPage = newDocument.page(at: 0) {
            let thumb = firstPage.thumbnail(of: CGSize(width: 200, height: 200), for: .mediaBox)
            document.thumbnailData = thumb.jpegData(compressionQuality: 0.85)
        }
        document.updatedAt = Date()
        CoreDataStack.shared.saveIfNeeded()
    }

    private func shareTapped() {
        guard let url = pdfURL() else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            showAlert(title: "File Missing", message: "PDF file not found on device.")
            return
        }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(activityVC, animated: true)
    }

    private func printTapped() {
        if pdfDocument == nil { loadPDF() }

        guard let pdfDocument,
              let pdfData = pdfDocument.dataRepresentation() else {
            showAlert(title: "Error", message: "Unable to print this PDF.")
            return
        }

        let printController = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.jobName = document.name ?? "Document"
        printInfo.outputType = .general

        printController.printInfo = printInfo
        printController.printingItem = pdfData
        printController.present(animated: true)
    }

    private func deleteTapped() {
        let name = document.name ?? "this document"
        let alert = UIAlertController(
            title: "Delete Document",
            message: "Are you sure you want to delete '\(name)'?",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            guard let self else { return }

            if let url = self.pdfURL() {
                try? FileManager.default.removeItem(at: url)
            }

            self.context.delete(self.document)
            CoreDataStack.shared.saveIfNeeded()
            self.navigationController?.popViewController(animated: true)
        })

        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }

    // MARK: - Alerts

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.view.tintColor = AppColors.primary
        present(alert, animated: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - PaddingLabel (pill)

private final class PaddingLabel: UILabel {
    var contentInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(
            width: s.width + contentInsets.left + contentInsets.right,
            height: s.height + contentInsets.top + contentInsets.bottom
        )
    }
}

// MARK: - Bottom bar (tabbar-like, no center button)

private final class ActionDockBar: UIView {

    var onTapShare: (() -> Void)?
    var onTapPrint: (() -> Void)?
    var onTapDelete: (() -> Void)?
    var onTapOrganize: (() -> Void)?

    var accentColor: UIColor = .systemRed { didSet { applyColors() } }
    var unselectedColor: UIColor = .systemRed { didSet { applyColors() } }
    var tabbarColor: UIColor = .white { didSet { setNeedsDisplay() } }

    private let share = ActionTabItem()
    private let organize = ActionTabItem()
    private let print = ActionTabItem()
    private let delete = ActionTabItem()

    private var shapeLayer: CAShapeLayer?

    private let stack: UIStackView = {
        let s = UIStackView()
        s.axis = .horizontal
        s.distribution = .fillEqually
        s.alignment = .fill
        s.spacing = 0
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        backgroundColor = .clear
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        clipsToBounds = false
        backgroundColor = .clear
        setup()
    }

    private func setup() {
        share.configure(title: "Share", systemImage: "square.and.arrow.up")
        organize.configure(title: "Organize", systemImage: "square.stack.3d.up")
        print.configure(title: "Print", systemImage: "printer")
        delete.configure(title: "Delete", systemImage: "trash")

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        [share, organize, print, delete].forEach { stack.addArrangedSubview($0) }

        share.onTap = { [weak self] in self?.onTapShare?() }
        organize.onTap = { [weak self] in self?.onTapOrganize?() }
        print.onTap = { [weak self] in self?.onTapPrint?() }
        delete.onTap = { [weak self] in self?.onTapDelete?() }

        applyColors()
    }

    private func applyColors() {
        [share, organize, print, delete].forEach {
            $0.selectedColor = accentColor
            $0.unselectedColor = unselectedColor
            $0.isSelected = true
        }
    }

    override func draw(_ rect: CGRect) {
        addShape()
    }

    private func addShape() {
        let sl = CAShapeLayer()
        sl.path = createPath()
        sl.fillColor = tabbarColor.cgColor
        sl.lineWidth = 0

        sl.shadowOffset = CGSize(width: 0, height: 0)
        sl.shadowRadius = 10
        sl.shadowColor = AppColors.shadowColor.cgColor
        sl.shadowOpacity = 0.3

        if let old = shapeLayer {
            layer.replaceSublayer(old, with: sl)
        } else {
            layer.insertSublayer(sl, at: 0)
        }
        shapeLayer = sl
    }

    private func createPath() -> CGPath {
        let h = bounds.height
        let w = bounds.width
        let cornerRadius: CGFloat = 34

        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: cornerRadius))
        path.addQuadCurve(to: CGPoint(x: cornerRadius, y: 0), controlPoint: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: w - cornerRadius, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: cornerRadius), controlPoint: CGPoint(x: w, y: 0))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.close()

        return path.cgPath
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let safeBottom: CGFloat = {
            if let window = self.window { return window.safeAreaInsets.bottom }
            return safeAreaInsets.bottom
        }()

        let dynamicBottomInset: CGFloat = safeBottom + 10
        let topInset: CGFloat = 12 // push content slightly down from the top

        [share, organize, print, delete].forEach { item in
            item.contentInsets.top = topInset
            item.contentInsets.bottom = dynamicBottomInset
        }

        shapeLayer?.path = createPath()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !clipsToBounds && !isHidden && alpha > 0 {
            for sub in subviews.reversed() {
                let p = sub.convert(point, from: self)
                if let res = sub.hitTest(p, with: event) { return res }
            }
        }
        return super.hitTest(point, with: event)
    }
}

private final class ActionTabItem: UIControl {

    var onTap: (() -> Void)?

    var selectedColor: UIColor = .systemRed { didSet { applyColors() } }
    var unselectedColor: UIColor = .gray { didSet { applyColors() } }

    override var isSelected: Bool { didSet { applyColors() } }

    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    private var iconTopConstraint: NSLayoutConstraint?
    private var titleLeadingConstraint: NSLayoutConstraint?
    private var titleTrailingConstraint: NSLayoutConstraint?
    private var titleBottomConstraint: NSLayoutConstraint?

    var contentInsets = UIEdgeInsets(top: 8, left: 10, bottom: 12, right: 10) {
        didSet { applyInsets() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isAccessibilityElement = true
        accessibilityTraits = .button

        iconView.contentMode = .scaleAspectFit
        titleLabel.font = AppFonts.medium(12)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1

        addSubview(iconView)
        addSubview(titleLabel)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        iconTopConstraint = iconView.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top)
        let iconCenterX = iconView.centerXAnchor.constraint(equalTo: centerXAnchor)
        let iconWidth = iconView.widthAnchor.constraint(equalToConstant: 24)
        let iconHeight = iconView.heightAnchor.constraint(equalToConstant: 24)

        let titleTop = titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 2)
        titleLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left)
        titleTrailingConstraint = titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right)
        titleBottomConstraint = titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -contentInsets.bottom)

        NSLayoutConstraint.activate([
            iconTopConstraint!, iconCenterX, iconWidth, iconHeight,
            titleTop, titleLeadingConstraint!, titleTrailingConstraint!, titleBottomConstraint!
        ])

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        applyColors()
    }

    func configure(title: String, systemImage: String) {
        titleLabel.text = title
        accessibilityLabel = title

        let img = UIImage(systemName: systemImage)?.withRenderingMode(.alwaysTemplate)
        iconView.image = img
        applyColors()
    }

    private func applyColors() {
        let tint = isSelected ? selectedColor : unselectedColor
        iconView.tintColor = tint
        titleLabel.textColor = tint
    }

    @objc private func tapped() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        onTap?()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let minSize = CGSize(width: 96, height: 72)
        var b = bounds
        let w = max(minSize.width, b.width)
        let h = max(minSize.height, b.height)
        let dx = (w - b.width) / 2
        let dy = (h - b.height) / 2
        b = b.insetBy(dx: -dx, dy: -dy)
        return b.contains(point)
    }

    private func applyInsets() {
        iconTopConstraint?.constant = contentInsets.top
        titleLeadingConstraint?.constant = contentInsets.left
        titleTrailingConstraint?.constant = -contentInsets.right
        titleBottomConstraint?.constant = -contentInsets.bottom
        setNeedsLayout()
    }
}

