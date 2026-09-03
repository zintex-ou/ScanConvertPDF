import UIKit

final class DocumentsHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "DocumentsHeaderView"
    
    private let container = UIStackView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = AppColors.background
        container.axis = .vertical
        container.spacing = 12
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }
    
    func configure(searchView: UIView, controls: UIStackView) {
        container.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if searchView.superview != nil { searchView.removeFromSuperview() }
        if controls.superview != nil { controls.removeFromSuperview() }

        container.addArrangedSubview(searchView)
        container.addArrangedSubview(controls)

        controls.heightAnchor.constraint(equalToConstant: 40).isActive = true
    }
}

