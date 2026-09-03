//
//  CenterButtonMenu.swift
//  ScanConvertPDF
//
//  Created by Developer on 19.01.2026.
//

import UIKit

// MARK: - Menu Item
struct CenterMenuAction {
    let title: String
    let icon: UIImage?
    let handler: () -> Void
    
    init(title: String, icon: UIImage?, handler: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.handler = handler
    }
    
    init(title: String, systemIcon: String, handler: @escaping () -> Void) {
        self.title = title
        self.icon = UIImage(systemName: systemIcon)
        self.handler = handler
    }
}

// MARK: - Center Button Menu
final class CenterButtonMenu: UIView {
    
    // MARK: - Public Properties
    
    /// Колір акценту (іконки та текст)
    var accentColor: UIColor = .systemRed {
        didSet { updateColors() }
    }
    
    /// Колір фону кнопок
    var buttonBackgroundColor: UIColor = AppColors.cellBackgroundHighlighted {
        didSet { updateColors() }
    }
    
    /// Колір затемнення фону
    var overlayColor: UIColor = UIColor.black.withAlphaComponent(0.4) {
        didSet { overlayView.backgroundColor = overlayColor }
    }
    
    /// Callback при закритті меню
    var onDismiss: (() -> Void)?
    
    // MARK: - Private Properties
    
    private let overlayView = UIView()
    private let containerView = UIView()
    private var actionButtons: [MenuActionButton] = []
    private var actions: [CenterMenuAction] = []
    
    private let columns: Int = 3
    private let buttonSize: CGFloat = 90
    private let buttonSpacing: CGFloat = 12
    private let containerPadding: CGFloat = 16
    private let cornerRadius: CGFloat = 24
    
    // MARK: - Init
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // Overlay (затемнення)
        overlayView.backgroundColor = overlayColor
        overlayView.alpha = 0
        addSubview(overlayView)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(overlayTapped))
        overlayView.addGestureRecognizer(tapGesture)
        
        // Container
        containerView.backgroundColor = AppColors.cellBackground
        containerView.layer.cornerRadius = cornerRadius
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: -4)
        containerView.layer.shadowRadius = 20
        containerView.layer.shadowOpacity = 0.15
        containerView.alpha = 0
        addSubview(containerView)
    }
    
    // MARK: - Public API
    
    /// Налаштувати дії меню
    func configure(actions: [CenterMenuAction]) {
        self.actions = actions
        rebuildButtons()
    }
    
    /// Показати меню
    func show(in parentView: UIView, above tabBar: UIView, animated: Bool = true) {
        parentView.addSubview(self)
        frame = parentView.bounds
        
        overlayView.frame = bounds
        
        layoutContainer(above: tabBar)
        
        if animated {
            // Проста анімація появи - тільки fade + scale
            containerView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                self.overlayView.alpha = 1
                self.containerView.alpha = 1
                self.containerView.transform = .identity
            }
            
            // Анімація появи кнопок
            for (index, button) in actionButtons.enumerated() {
                button.alpha = 0
                button.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
                
                UIView.animate(withDuration: 0.2, delay: Double(index) * 0.03, options: .curveEaseOut) {
                    button.transform = .identity
                    button.alpha = 1
                }
            }
        } else {
            overlayView.alpha = 1
            containerView.alpha = 1
        }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    
    /// Сховати меню
    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseIn) {
                self.overlayView.alpha = 0
                self.containerView.alpha = 0
                self.containerView.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
            } completion: { _ in
                self.removeFromSuperview()
                self.containerView.transform = .identity
                self.onDismiss?()
                completion?()
            }
        } else {
            removeFromSuperview()
            onDismiss?()
            completion?()
        }
    }
    
    // MARK: - Private Methods
    
    private func rebuildButtons() {
        actionButtons.forEach { $0.removeFromSuperview() }
        actionButtons.removeAll()
        
        for (index, action) in actions.enumerated() {
            let button = MenuActionButton()
            button.configure(icon: action.icon, title: action.title)
            button.accentColor = accentColor
            button.backgroundColor = buttonBackgroundColor
            button.tag = index
            button.addTarget(self, action: #selector(actionButtonTapped(_:)), for: .touchUpInside)
            containerView.addSubview(button)
            actionButtons.append(button)
        }
    }
    
    private func layoutContainer(above tabBar: UIView) {
        let rows = Int(ceil(Double(actions.count) / Double(columns)))
        let contentWidth = CGFloat(columns) * buttonSize + CGFloat(columns - 1) * buttonSpacing
        let contentHeight = CGFloat(rows) * buttonSize + CGFloat(rows - 1) * buttonSpacing
        
        let containerWidth = contentWidth + containerPadding * 2
        let containerHeight = contentHeight + containerPadding * 2
        
        let tabBarFrame = tabBar.convert(tabBar.bounds, to: self)
        
        containerView.frame = CGRect(
            x: (bounds.width - containerWidth) / 2,
            y: tabBarFrame.minY - containerHeight - 16,
            width: containerWidth,
            height: containerHeight
        )
        
        // Layout buttons in grid (3 columns)
        for (index, button) in actionButtons.enumerated() {
            let row = index / columns
            let col = index % columns
            
            let x = containerPadding + CGFloat(col) * (buttonSize + buttonSpacing)
            let y = containerPadding + CGFloat(row) * (buttonSize + buttonSpacing)
            
            button.frame = CGRect(x: x, y: y, width: buttonSize, height: buttonSize)
        }
    }
    
    private func updateColors() {
        for button in actionButtons {
            button.accentColor = accentColor
            button.backgroundColor = buttonBackgroundColor
        }
    }
    
    @objc private func overlayTapped() {
        dismiss()
    }
    
    @objc private func actionButtonTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < actions.count else { return }
        
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        
        dismiss { [weak self] in
            self?.actions[index].handler()
        }
    }
}

// MARK: - Menu Action Button
private final class MenuActionButton: UIControl {
    
    var accentColor: UIColor = .systemRed {
        didSet { updateAppearance() }
    }
    
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    
    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.95, y: 0.95) : .identity
                self.alpha = self.isHighlighted ? 0.7 : 1.0
            }
        }
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
        layer.cornerRadius = 16
        
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = accentColor
        addSubview(iconView)
        
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = accentColor
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -10),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),
            
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 6),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
        ])
    }
    
    func configure(icon: UIImage?, title: String) {
        let config = UIImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        iconView.image = icon?.withConfiguration(config)
        titleLabel.text = title
    }
    
    private func updateAppearance() {
        iconView.tintColor = accentColor
        titleLabel.textColor = accentColor
    }
}

// MARK: - DockTabBar Extension
extension DockTabBar {
    
    /// Повернути іконку центральної кнопки (+ → ×)
    func setCenterButtonToClose(_ isClose: Bool, animated: Bool = true) {
        let rotation: CGFloat = isClose ? .pi / 4 : 0  // 45° для "×"
        
        if animated {
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = centerButtonIcon.layer.presentation()?.value(forKeyPath: "transform.rotation.z") ?? 0
            animation.toValue = rotation
            animation.duration = 0.25
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            centerButtonIcon.layer.removeAnimation(forKey: "rotationAnimation")
            centerButtonIcon.layer.add(animation, forKey: "rotationAnimation")
            
            // Встановлюємо кінцеве значення
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            centerButtonIcon.layer.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
            CATransaction.commit()
        } else {
            centerButtonIcon.layer.removeAnimation(forKey: "rotationAnimation")
            centerButtonIcon.layer.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
        }
    }
}

// MARK: - Center Button Enable/Disable
extension DockTabBar {
    func setCenterButtonEnabled(_ enabled: Bool, animated: Bool = true) {
        centerButton.isEnabled = enabled
        centerButton.isUserInteractionEnabled = enabled

        let alpha: CGFloat = enabled ? 1.0 : 0.25

        let changes = {
            self.centerButton.alpha = alpha
            self.centerButtonIcon.alpha = enabled ? 1.0 : 0.6
        }

        if animated {
            UIView.animate(withDuration: 0.18, animations: changes)
        } else {
            changes()
        }
    }
}
