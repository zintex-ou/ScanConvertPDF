//
//  SectionHeaderView.swift
//  ScanConvertPDF
//
//  Created by Developer
//

import UIKit

class SectionHeaderView: UICollectionReusableView {
    
    static let identifier = "SectionHeaderView"
    
    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AppFonts.semibold(16)
        label.textColor = AppColors.textSecondary
        return label
    }()
    
    private lazy var separatorView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = AppColors.lightGray
        return view
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        addSubview(titleLabel)
        addSubview(separatorView)
        
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            
            separatorView.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 12),
            separatorView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            separatorView.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            separatorView.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
    
    func configure(title: String) {
        titleLabel.text = title
    }
}
