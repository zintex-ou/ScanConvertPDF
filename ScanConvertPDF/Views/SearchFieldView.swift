//
//  SearchFieldView.swift
//  ScanConvertPDF
//
//  Created by Developer on 20.01.2026.
//

import UIKit


final class SearchFieldView: UIView {

    let textField = UITextField()

    var onTextChanged: ((String) -> Void)?
    var onSearchTapped: ((String) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = AppColors.cellBackground
        layer.cornerRadius = 16
        clipsToBounds = true

        // лупа
        let icon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
        icon.tintColor = .systemGray
        icon.translatesAutoresizingMaskIntoConstraints = false

        textField.attributedPlaceholder = NSAttributedString(
            string: "Search",
            attributes: [.foregroundColor: UIColor.systemGray]
        )
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.returnKeyType = .search
        textField.clearButtonMode = .whileEditing
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(textField)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),

            textField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        textField.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        textField.addTarget(self, action: #selector(editingDidEndOnExit), for: .editingDidEndOnExit)
    }

    @objc private func textChanged() {
        onTextChanged?(textField.text ?? "")
    }

    @objc private func editingDidEndOnExit() {
        onSearchTapped?(textField.text ?? "")
        textField.resignFirstResponder()
    }
}
