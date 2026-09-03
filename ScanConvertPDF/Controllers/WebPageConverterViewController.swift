//
//  WebPageConverterViewController.swift
//  ScanConvertPDF
//
//  Created by Developer
//

import UIKit
import WebKit
import PDFKit
import CoreData

final class WebPageConverterViewController: UIViewController {

    // MARK: - Properties

    private var currentURL: URL?
    private var urlContainerBottomConstraint: NSLayoutConstraint?
    private var urlContainerHeightConstraint: NSLayoutConstraint?

    /// Важливо: під час reset ми вантажимо about:blank (або HTML), і це тригерить didFinish.
    /// Щоб didFinish не переключив UI назад на actions — ігноруємо callbacks під час reset.
    private var isResettingWebView: Bool = false

    private enum BottomBarMode {
        case input      // url + go (або spinner)
        case actions    // save pdf + reset
    }

    private var bottomBarMode: BottomBarMode = .input {
        didSet {
            print("bottomBarMode -> \(bottomBarMode == .input ? "input" : "actions")")
            applyBottomBarMode()
        }
    }

    private var isGoLoading: Bool = false {
        didSet {
            print("isGoLoading -> \(isGoLoading)")
            applyGoLoadingState()
        }
    }

    // MARK: - UI Elements

    private lazy var urlContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.cellBackground
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: -2)
        view.layer.shadowRadius = 8
        view.layer.shadowOpacity = 0.08
        return view
    }()
    
    /// Контентна частина бару (висота 70), щоб контент НЕ “плавав” при клавіатурі
    private lazy var urlContentView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        return v
    }()

    private lazy var urlTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.placeholder = "Enter URL (e.g., https://example.com)"
        tf.font = AppFonts.regular(15)
        tf.textColor = AppColors.textPrimary
        tf.backgroundColor = AppColors.lightGray
        tf.layer.cornerRadius = 12
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.keyboardType = .URL
        tf.returnKeyType = .go
        tf.clearButtonMode = .whileEditing
        tf.enablesReturnKeyAutomatically = true
        tf.delegate = self

        let leftView = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 44))
        let iconView = UIImageView(image: UIImage(systemName: "globe"))
        iconView.tintColor = AppColors.textSecondary
        iconView.frame = CGRect(x: 12, y: 12, width: 20, height: 20)
        leftView.addSubview(iconView)
        tf.leftView = leftView
        tf.leftViewMode = .always

        return tf
    }()

    /// Go button (тільки іконка), 44x44
    private lazy var goButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = AppColors.primary
        config.baseForegroundColor = .white
        config.cornerStyle = .fixed
        config.background.cornerRadius = 12

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        config.image = UIImage(systemName: "arrow.right", withConfiguration: symbolConfig)
        config.imagePlacement = .all
        config.contentInsets = .init(top: 0, leading: 0, bottom: 0, trailing: 0)

        button.configuration = config
        button.addTarget(self, action: #selector(goButtonTapped), for: .touchUpInside)
        return button
    }()

    /// Spinner container (показуємо замість Go), 44x44
    private lazy var goSpinnerView: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = AppColors.primary
        v.layer.cornerRadius = 12
        v.isHidden = true
        return v
    }()

    private lazy var goSpinner: UIActivityIndicatorView = {
        let sp = UIActivityIndicatorView(style: .medium)
        sp.translatesAutoresizingMaskIntoConstraints = false
        sp.color = .white
        sp.hidesWhenStopped = true
        return sp
    }()

    /// Save as PDF button
    private lazy var savePDFButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = AppColors.primary
        config.baseForegroundColor = .white
        config.cornerStyle = .fixed
        config.background.cornerRadius = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)

        let imageConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        config.image = UIImage(systemName: "arrow.down.doc", withConfiguration: imageConfig)
        config.imagePadding = 8
        config.attributedTitle = AttributedString("Save PDF", attributes: AttributeContainer([
            .font: AppFonts.semibold(15)
        ]))

        button.configuration = config
        button.addTarget(self, action: #selector(convertTapped), for: .touchUpInside)
        return button
    }()

    /// Reset button
    private lazy var resetButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = AppColors.lightGray
        config.baseForegroundColor = AppColors.textPrimary
        config.cornerStyle = .fixed
        config.background.cornerRadius = 12
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)

        let imageConfig = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        config.image = UIImage(systemName: "arrow.counterclockwise", withConfiguration: imageConfig)
        config.imagePadding = 8
        config.attributedTitle = AttributedString("Reset", attributes: AttributeContainer([
            .font: AppFonts.semibold(15)
        ]))

        button.configuration = config
        button.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        return button
    }()

    /// Stack для 2х кнопок (однаковий розмір)
    private lazy var actionsStackView: UIStackView = {
        let sv = UIStackView(arrangedSubviews: [savePDFButton, resetButton])
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.alignment = .fill
        sv.distribution = .fillEqually
        sv.spacing = 12
        sv.isHidden = true
        return sv
    }()

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.backgroundColor = AppColors.lightGray
        wv.scrollView.keyboardDismissMode = .interactive
        return wv
    }()

    private lazy var progressView: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.progressTintColor = AppColors.primary
        pv.trackTintColor = AppColors.lightGray
        pv.isHidden = true
        return pv
    }()

    private lazy var placeholderView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = UIImage(systemName: "doc.text.magnifyingglass")
        iconView.tintColor = AppColors.textSecondary.withAlphaComponent(0.5)
        iconView.contentMode = .scaleAspectFit

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Enter a URL to convert to PDF"
        label.font = AppFonts.regular(16)
        label.textColor = AppColors.textSecondary
        label.textAlignment = .center

        view.addSubview(iconView)
        view.addSubview(label)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            iconView.widthAnchor.constraint(equalToConstant: 60),
            iconView.heightAnchor.constraint(equalToConstant: 60),

            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        return view
    }()

    /// Центровий індикатор для створення PDF
    private lazy var loadingIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.color = AppColors.primary
        indicator.hidesWhenStopped = true
        return indicator
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        setupKeyboardObservers()

        bottomBarMode = .input
        isGoLoading = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        urlContainerHeightConstraint?.constant = 70 + view.safeAreaInsets.bottom
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = AppColors.background

        view.addSubview(progressView)
        view.addSubview(webView)
        view.addSubview(placeholderView)
        view.addSubview(urlContainerView)
        view.addSubview(loadingIndicator)

        urlContainerView.addSubview(urlContentView)

        // Input controls
        urlContentView.addSubview(urlTextField)
        urlContentView.addSubview(goButton)
        urlContentView.addSubview(goSpinnerView)
        goSpinnerView.addSubview(goSpinner)

        // Actions stack
        urlContentView.addSubview(actionsStackView)

        let tapWeb = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapWeb.cancelsTouchesInView = false
        webView.addGestureRecognizer(tapWeb)

        let tapPlaceholder = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapPlaceholder.cancelsTouchesInView = false
        placeholderView.addGestureRecognizer(tapPlaceholder)

        urlContainerHeightConstraint = urlContainerView.heightAnchor.constraint(equalToConstant: 70)

        NSLayoutConstraint.activate([
            // Progress
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 3),

            // Bottom bar
            urlContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            urlContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // urlContentView
            urlContentView.topAnchor.constraint(equalTo: urlContainerView.topAnchor),
            urlContentView.leadingAnchor.constraint(equalTo: urlContainerView.leadingAnchor),
            urlContentView.trailingAnchor.constraint(equalTo: urlContainerView.trailingAnchor),
            urlContentView.heightAnchor.constraint(equalToConstant: 70),

            // Web / placeholder
            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: urlContainerView.topAnchor),

            placeholderView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: urlContainerView.topAnchor),

            // Loader
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            // urlTextField
            urlTextField.leadingAnchor.constraint(equalTo: urlContentView.leadingAnchor, constant: 16),
            urlTextField.centerYAnchor.constraint(equalTo: urlContentView.centerYAnchor),
            urlTextField.heightAnchor.constraint(equalToConstant: 44),

            // Go button 44x44
            goButton.trailingAnchor.constraint(equalTo: urlContentView.trailingAnchor, constant: -16),
            goButton.centerYAnchor.constraint(equalTo: urlContentView.centerYAnchor),
            goButton.widthAnchor.constraint(equalToConstant: 44),
            goButton.heightAnchor.constraint(equalToConstant: 44),

            urlTextField.trailingAnchor.constraint(equalTo: goButton.leadingAnchor, constant: -12),

            // Spinner 44x44
            goSpinnerView.trailingAnchor.constraint(equalTo: urlContentView.trailingAnchor, constant: -16),
            goSpinnerView.centerYAnchor.constraint(equalTo: urlContentView.centerYAnchor),
            goSpinnerView.widthAnchor.constraint(equalToConstant: 44),
            goSpinnerView.heightAnchor.constraint(equalToConstant: 44),

            goSpinner.centerXAnchor.constraint(equalTo: goSpinnerView.centerXAnchor),
            goSpinner.centerYAnchor.constraint(equalTo: goSpinnerView.centerYAnchor),

            // Actions stack
            actionsStackView.leadingAnchor.constraint(equalTo: urlContentView.leadingAnchor, constant: 16),
            actionsStackView.trailingAnchor.constraint(equalTo: urlContentView.trailingAnchor, constant: -16),
            actionsStackView.centerYAnchor.constraint(equalTo: urlContentView.centerYAnchor),
            actionsStackView.heightAnchor.constraint(equalToConstant: 44),
        ])

        urlContainerHeightConstraint?.isActive = true

        urlContainerBottomConstraint = urlContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        urlContainerBottomConstraint?.isActive = true

        webView.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil)

        applyBottomBarMode()
        applyGoLoadingState()
    }

    private func setupNavigationBar() {
        title = "Web to PDF"
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

        // Close button (left bar item)
        let closeButton = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(closeTapped)
        )
        closeButton.tintColor = AppColors.primary
        navigationItem.leftBarButtonItem = closeButton
    }

    private func setupKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            progressView.progress = Float(webView.estimatedProgress)
        }
    }

    // MARK: - UI State

    private func applyBottomBarMode() {
        switch bottomBarMode {
        case .input:
            actionsStackView.isHidden = true
            urlTextField.isHidden = false
            applyGoLoadingState()

        case .actions:
            urlTextField.isHidden = true
            goButton.isHidden = true
            goSpinnerView.isHidden = true
            goSpinner.stopAnimating()
            actionsStackView.isHidden = false
        }
    }

    private func applyGoLoadingState() {
        guard bottomBarMode == .input else { return }

        if isGoLoading {
            goButton.isHidden = true
            goSpinnerView.isHidden = false
            goSpinner.startAnimating()
            urlTextField.isEnabled = false
        } else {
            goSpinner.stopAnimating()
            goSpinnerView.isHidden = true
            goButton.isHidden = false
            urlTextField.isEnabled = true
        }
    }

    // MARK: - Actions

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func goButtonTapped() { loadURL() }

    @objc private func resetTapped() {
        print("resetTapped")

        isResettingWebView = true

        webView.stopLoading()
        // щоб WKWebView очистився (але didFinish буде ігнорований через isResettingWebView)
        webView.loadHTMLString("", baseURL: nil)

        currentURL = nil
        urlTextField.text = nil

        progressView.isHidden = true
        progressView.progress = 0

        placeholderView.isHidden = false
        webView.isHidden = true

        bottomBarMode = .input
        isGoLoading = false
    }

    @objc private func backgroundTapped() {
        view.endEditing(true)
    }

    private func loadURL() {
        guard var urlString = urlTextField.text, !urlString.isEmpty else { return }
        urlTextField.resignFirstResponder()

        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        guard let url = URL(string: urlString) else {
            print( "Invalid URL - Please enter a valid URL")
            return
        }

        print("loadURL -> \(url.absoluteString)")

        currentURL = url
        placeholderView.isHidden = true
        webView.isHidden = false

        progressView.isHidden = false
        progressView.progress = 0

        bottomBarMode = .input
        isGoLoading = true

        webView.load(URLRequest(url: url))
    }

    @objc private func convertTapped() {
        print("convertTapped")

        loadingIndicator.startAnimating()
        savePDFButton.isEnabled = false
        resetButton.isEnabled = false

        webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loadingIndicator.stopAnimating()
                self.savePDFButton.isEnabled = true
                self.resetButton.isEnabled = true

                switch result {
                case .success(let data):
                    self.savePDFToCoreData(data: data)
                case .failure(let error):
                    print("Error", error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Keyboard

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let frameValue = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
            let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
            let curveRaw = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else { return }

        let keyboardFrameInView = view.convert(frameValue.cgRectValue, from: nil)
        let overlap = max(0, view.bounds.maxY - keyboardFrameInView.minY)

        let safeBottom = view.safeAreaInsets.bottom
        let lift = max(0, overlap - safeBottom)

        urlContainerBottomConstraint?.constant = -lift

        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard
            let userInfo = notification.userInfo,
            let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double,
            let curveRaw = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt
        else {
            urlContainerBottomConstraint?.constant = 0
            view.layoutIfNeeded()
            return
        }

        urlContainerBottomConstraint?.constant = 0
        let options = UIView.AnimationOptions(rawValue: curveRaw << 16)
        UIView.animate(withDuration: duration, delay: 0, options: options) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Core Data Save

    private func savePDFToCoreData(data: Data) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let pageName: String = {
            if let url = currentURL {
                let host = url.host ?? "webpage"
                return "WebPage_\(host)_\(df.string(from: Date()))"
            } else {
                return "WebPage_\(df.string(from: Date()))"
            }
        }()

        let fileName = "\(UUID().uuidString).pdf"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
             print("Failed to save PDF: \(error.localizedDescription)")
            return
        }

        var pageCount = 1
        var thumbData: Data?

        if let pdfDoc = PDFDocument(data: data) {
            pageCount = pdfDoc.pageCount
            if let firstPage = pdfDoc.page(at: 0),
               let thumb = makePDFThumbnail(page: firstPage, targetSize: CGSize(width: 320, height: 320)) {
                thumbData = thumb.jpegData(compressionQuality: 0.92)
            }
        }

        let ctx = CoreDataStack.shared.context
        let cd = CDDocument(context: ctx)
        let now = Date()

        cd.id = UUID()
        cd.name = pageName
        cd.createdAt = now
        cd.updatedAt = now
        cd.pdfFileName = fileName
        cd.sizeBytes = Int64(data.count)
        cd.pageCount = Int16(pageCount)
        cd.thumbnailData = thumbData

        CoreDataStack.shared.saveIfNeeded()

        ToastAlertViewController.present(over: self,
                                        message: "Done",
                                        iconName: "checkmark-image",
                                        autoDismissAfter: 1.2) { [weak self] in
            self?.exitController()
        }

    }
    
    private func exitController() {
        if let nav = navigationController,
           nav.viewControllers.first != self {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func makePDFThumbnail(page: PDFPage, targetSize: CGSize) -> UIImage? {
        guard let pageRef = page.pageRef else { return nil }

        let pageRect = pageRef.getBoxRect(.mediaBox)
        guard pageRect.width > 0, pageRect.height > 0 else { return nil }

        let scale = max(targetSize.width / pageRect.width, targetSize.height / pageRect.height)
        let scaledW = pageRect.width * scale
        let scaledH = pageRect.height * scale
        let tx = (targetSize.width - scaledW) / 2.0
        let ty = (targetSize.height - scaledH) / 2.0

        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = UIScreen.main.scale

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))

            let cg = ctx.cgContext
            cg.saveGState()
            cg.translateBy(x: 0, y: targetSize.height)
            cg.scaleBy(x: 1, y: -1)
            cg.translateBy(x: tx, y: ty)
            cg.scaleBy(x: scale, y: scale)
            cg.drawPDFPage(pageRef)
            cg.restoreGState()
        }
    }

    // MARK: - Alerts
    
    
    deinit {
        webView.removeObserver(self, forKeyPath: "estimatedProgress")
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - UITextFieldDelegate

extension WebPageConverterViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        loadURL()
        return true
    }
}

// MARK: - WKNavigationDelegate

extension WebPageConverterViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if isResettingWebView {
            print("ignore didStart (reset)")
            return
        }
        print("didStartProvisionalNavigation")
        progressView.isHidden = false
        isGoLoading = true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isResettingWebView {
            print("ignore didFinish (reset) url=\(webView.url?.absoluteString ?? "nil")")
            isResettingWebView = false
            return
        }

        let urlStr = webView.url?.absoluteString ?? "nil"
        print("didFinish url=\(urlStr)")

        progressView.isHidden = true
        isGoLoading = false

        // Не показуємо actions для about:blank
        if urlStr == "about:blank" {
            print("didFinish about:blank -> keep input mode")
            return
        }

        if let url = webView.url {
            urlTextField.text = url.absoluteString
            currentURL = url
        }

        bottomBarMode = .actions
        print("actionsStackView hidden? \(actionsStackView.isHidden)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if isResettingWebView {
            print("ignore didFail (reset): \(error.localizedDescription)")
            isResettingWebView = false
            return
        }

        print("didFail: \(error.localizedDescription)")
        progressView.isHidden = true
        isGoLoading = false

        if (error as NSError).code != NSURLErrorCancelled {
            print("Failed to load page: \(error.localizedDescription)")
        }

        bottomBarMode = .input
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if isResettingWebView { isResettingWebView = false; return }

        progressView.isHidden = true
        isGoLoading = false
        bottomBarMode = .input

        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }

        let msg = userFriendlyErrorMessage(for: nsError)

        ToastAlertViewController.present(
            over: self,
            message: msg,
            iconName: "error-image",
            autoDismissAfter: 1.4
        )
    }

    private func showErrorToast(_ message: String) {
        ToastAlertViewController.present(
            over: self,
            message: message,
            iconName: "error-image",
            autoDismissAfter: 1.4
        )
    }
    
    private func userFriendlyErrorMessage(for error: NSError) -> String {
        switch error.code {
        case NSURLErrorCannotFindHost:
            return "Host not found"
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection"
        case NSURLErrorTimedOut:
            return "Request timed out"
        case NSURLErrorUnsupportedURL, NSURLErrorBadURL:
            return "Invalid URL"
        default:
            return "Failed to load page"
        }
    }
}
