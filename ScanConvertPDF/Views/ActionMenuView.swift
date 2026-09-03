//
//  ActionMenuView.swift
//  ScanConvertPDF
//
//  Created by Developer
//

import UIKit

protocol ActionMenuViewDelegate: AnyObject {
    func actionMenuDidSelectScan()
    func actionMenuDidSelectGallery()
    func actionMenuDidSelectWebPage()
    func actionMenuDidSelectDocuments()
}

class ActionMenuView: UIView {
    
    weak var delegate: ActionMenuViewDelegate?
    
    private lazy var containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.lightGray
        view.layer.cornerRadius = AppConstants.cornerRadius
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOffset = CGSize(width: 0, height: 4)
        view.layer.shadowRadius = 20
        view.layer.shadowOpacity = 0.15
        return view
    }()
    
    private lazy var stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.distribution = .fillEqually
        sv.spacing = 12
        return sv
    }()
    
    private lazy var topRowStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.spacing = 12
        return sv
    }()
    
    private lazy var bottomRowStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .fillEqually
        sv.spacing = 12
        return sv
    }()
    
    private lazy var scanButton: ActionButton = {
        let button = ActionButton(title: "Scan", icon: "viewfinder")
        button.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var galleryButton: ActionButton = {
        let button = ActionButton(title: "Gallery", icon: "photo")
        button.addTarget(self, action: #selector(galleryTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var webPageButton: ActionButton = {
        let button = ActionButton(title: "Web Page", icon: "globe")
        button.addTarget(self, action: #selector(webPageTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var documentsButton: ActionButton = {
        let button = ActionButton(title: "Documents", icon: "doc.on.doc")
        button.addTarget(self, action: #selector(documentsTapped), for: .touchUpInside)
        return button
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        addSubview(containerView)
        containerView.addSubview(stackView)
        
        topRowStack.addArrangedSubview(scanButton)
        topRowStack.addArrangedSubview(galleryButton)
        
        bottomRowStack.addArrangedSubview(webPageButton)
        bottomRowStack.addArrangedSubview(documentsButton)
        
        stackView.addArrangedSubview(topRowStack)
        stackView.addArrangedSubview(bottomRowStack)
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16)
        ])
    }
    
    @objc private func scanTapped() {
        delegate?.actionMenuDidSelectScan()
    }
    
    @objc private func galleryTapped() {
        delegate?.actionMenuDidSelectGallery()
    }
    
    @objc private func webPageTapped() {
        delegate?.actionMenuDidSelectWebPage()
    }
    
    @objc private func documentsTapped() {
        delegate?.actionMenuDidSelectDocuments()
    }
}

// MARK: - ActionButton

class ActionButton: UIButton {
    
    init(title: String, icon: String) {
        super.init(frame: .zero)
        
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .white
        config.baseForegroundColor = AppColors.primary
        config.cornerStyle = .medium
        
        let imageConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        config.image = UIImage(systemName: icon, withConfiguration: imageConfig)
        config.imagePlacement = .top
        config.imagePadding = 8
        
        config.title = title
        config.attributedTitle = AttributedString(title, attributes: AttributeContainer([
            .font: AppFonts.medium(13)
        ]))
        
        configuration = config
        
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 4
        layer.shadowOpacity = 0.05
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
