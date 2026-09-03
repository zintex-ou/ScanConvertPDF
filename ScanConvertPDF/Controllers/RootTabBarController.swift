//
//  RootTabBarController.swift
//  ScanConvertPDF
//
//  Created by Developer on 19.01.2026.
//

import Foundation
import UIKit

// MARK: - Delegate Protocol (розширений)
protocol RootTabBarControllerDelegate: AnyObject {
    func tabBarController(_ tabBarController: RootTabBarController,
                          shouldSelect viewController: UIViewController,
                          at index: Int) -> Bool
    func tabBarController(_ tabBarController: RootTabBarController,
                          didSelect viewController: UIViewController,
                          at index: Int)
    /// Викликається при повторному натисканні на вже вибрану вкладку
    func tabBarController(_ tabBarController: RootTabBarController,
                          didReselect viewController: UIViewController,
                          at index: Int)
    /// Викликається перед анімацією переходу
    func tabBarController(_ tabBarController: RootTabBarController,
                          animationControllerForTransitionFrom fromVC: UIViewController,
                          to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning?
}

extension RootTabBarControllerDelegate {
    func tabBarController(_ tabBarController: RootTabBarController,
                          shouldSelect viewController: UIViewController,
                          at index: Int) -> Bool { true }
    func tabBarController(_ tabBarController: RootTabBarController,
                          didSelect viewController: UIViewController,
                          at index: Int) {}
    func tabBarController(_ tabBarController: RootTabBarController,
                          didReselect viewController: UIViewController,
                          at index: Int) {}
    func tabBarController(_ tabBarController: RootTabBarController,
                          animationControllerForTransitionFrom fromVC: UIViewController,
                          to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? { nil }
}

// MARK: - Transition Style
enum TabBarTransitionStyle {
    case none
    case crossDissolve
    case slide
    case custom
}

// MARK: - RootTabBarController
final class RootTabBarController: UIViewController {

    // MARK: - Public Properties
    public let dockTabBar = DockTabBar()
    public private(set) var viewControllers: [UIViewController] = []
    public var actionTabs: [Int: () -> Void] = [:]
    public weak var delegate: RootTabBarControllerDelegate?
    public private(set) var selectedViewController: UIViewController?
    
    /// На яких вкладках центральна кнопка має бути неактивною
    public var centerButtonDisabledTabs: Set<Int> = [] {
        didSet { updateCenterButtonState(animated: false) }
    }
    
    /// Стиль анімації переходу між вкладками
    public var transitionStyle: TabBarTransitionStyle = .crossDissolve
    
    /// Тривалість анімації переходу
    public var transitionDuration: TimeInterval = 0.22
    
    /// Чи повертатись до root при повторному натисканні на NavigationController
    public var popsToRootOnReselect: Bool = true
    
    /// Чи скролити до верху при повторному натисканні на ScrollView
    public var scrollsToTopOnReselect: Bool = true

    // backing store
    private var _selectedIndex: Int = 0

    /// Як у UITabBarController
    public var selectedIndex: Int {
        get { _selectedIndex }
        set { selectTab(at: newValue, animated: false, userInitiated: false) }
    }

    // MARK: - Private Properties
    private let containerView = UIView()
    private var tabBarHeightConstraint: NSLayoutConstraint!
    private var tabBarBottomConstraint: NSLayoutConstraint!
    private var isTabBarHidden: Bool = false
    private var tabBarItemObservers: [NSKeyValueObservation] = []
    
    /// Базова висота таббара (без safe area)
    private let baseTabBarHeight: CGFloat = 58
    
    /// Відступ контенту від верху таббара (для компенсації скруглених кутів)
    /// Збільшіть це значення, щоб контент закінчувався вище
    /// Зменшіть, щоб контент закінчувався нижче (ближче до таббара)
    public var contentInsetOffset: CGFloat = 30 {
        didSet {
            updateAdditionalSafeAreaInsets(force: true)
        }
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTabBarCallbacks()
        setupNotifications()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTabBarLayoutMetrics()
    }
    
    deinit {
        tabBarItemObservers.forEach { $0.invalidate() }
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API
    
    /// Встановлює контролери вкладок
    public func setViewControllers(_ controllers: [UIViewController], animated: Bool) {
        removeAllChildren()
        clearObservers()

        viewControllers = controllers

        for vc in viewControllers {
            addChild(vc)
            vc.didMove(toParent: self)
        }

        reloadTabBarItems()
        observeTabBarItems()

        let maxIndex = max(0, viewControllers.count - 1)
        _selectedIndex = min(_selectedIndex, maxIndex)
        
        selectTab(at: _selectedIndex, animated: animated, userInitiated: false)
    }
    
    /// Програмне переключення на вкладку з анімацією
    public func setSelectedIndex(_ index: Int, animated: Bool) {
        selectTab(at: index, animated: animated, userInitiated: false)
    }
    
    /// Програмне переключення на контролер
    public func setSelectedViewController(_ viewController: UIViewController, animated: Bool) {
        guard let index = viewControllers.firstIndex(of: viewController) else { return }
        selectTab(at: index, animated: animated, userInitiated: false)
    }
    
    /// Отримати контролер за індексом
    public func viewController(at index: Int) -> UIViewController? {
        guard index >= 0, index < viewControllers.count else { return nil }
        return viewControllers[index]
    }
    
    /// Отримати індекс контролера
    public func index(of viewController: UIViewController) -> Int? {
        return viewControllers.firstIndex(of: viewController)
    }

    // MARK: - Badge API
    
    /// Встановити бейдж для вкладки
    public func setBadge(_ value: String?, at index: Int) {
        dockTabBar.setBadge(value, at: index)
    }
    
    /// Встановити числовий бейдж
    public func setBadgeCount(_ count: Int, at index: Int) {
        if count <= 0 {
            setBadge(nil, at: index)
        } else if count > 99 {
            setBadge("99+", at: index)
        } else {
            setBadge("\(count)", at: index)
        }
    }
    
    /// Очистити всі бейджі
    public func clearAllBadges() {
        for i in 0..<viewControllers.count {
            setBadge(nil, at: i)
        }
    }

    // MARK: - Tab Bar Visibility
    
    /// Показати/сховати таббар
    public func setTabBar(hidden: Bool,
                          animated: Bool = true,
                          duration: TimeInterval = 0.28,
                          completion: (() -> Void)? = nil) {
        guard isTabBarHidden != hidden else { completion?(); return }
        isTabBarHidden = hidden

        view.layoutIfNeeded()

        let barHeight = dockTabBar.frame.height

        let applySafeArea: () -> Void = { [weak self] in
            self?.updateAdditionalSafeAreaInsets()
        }

        if hidden {
            dockTabBar.isHidden = false
            dockTabBar.isUserInteractionEnabled = false

            let animations = {
                self.tabBarBottomConstraint.constant = barHeight
                self.dockTabBar.alpha = 0
                self.view.layoutIfNeeded()
            }

            let finish: (Bool) -> Void = { _ in
                self.dockTabBar.isHidden = true
                self.dockTabBar.alpha = 1
                self.tabBarBottomConstraint.constant = 0
                self.dockTabBar.isUserInteractionEnabled = true
                applySafeArea()
                completion?()
            }

            applySafeArea()

            if animated {
                UIView.animate(withDuration: duration,
                               delay: 0,
                               options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                               animations: animations,
                               completion: finish)
            } else {
                animations()
                finish(true)
            }

        } else {
            dockTabBar.isHidden = false
            dockTabBar.alpha = 0
            tabBarBottomConstraint.constant = barHeight
            view.layoutIfNeeded()

            applySafeArea()

            UIView.animate(withDuration: animated ? duration : 0,
                           delay: 0,
                           options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
                           animations: {
                self.tabBarBottomConstraint.constant = 0
                self.dockTabBar.alpha = 1
                self.view.layoutIfNeeded()
            }, completion: { _ in
                completion?()
            })
        }
    }
    
    /// Поточний стан видимості таббара
    public var isTabBarVisible: Bool {
        return !isTabBarHidden && !dockTabBar.isHidden
    }

    // MARK: - Tab Bar Appearance
    
    /// Колір фону таббара
    public var tabBarBackgroundColor: UIColor {
        get { dockTabBar.tabbarColor }
        set { dockTabBar.tabbarColor = newValue }
    }
    
    /// Колір виділеного елемента
    public var tabBarTintColor: UIColor {
        get { dockTabBar.centerButtonColor }
        set { dockTabBar.centerButtonColor = newValue }
    }
    
    /// Колір невиділеного елемента
    public var tabBarUnselectedTintColor: UIColor {
        get { dockTabBar.unselectedItemColor }
        set { dockTabBar.unselectedItemColor = newValue }
    }

    // MARK: - Status bar / rotations forwarding
    override var childForStatusBarStyle: UIViewController? { selectedViewController }
    override var childForStatusBarHidden: UIViewController? { selectedViewController }
    override var childForHomeIndicatorAutoHidden: UIViewController? { selectedViewController }
    override var childForScreenEdgesDeferringSystemGestures: UIViewController? { selectedViewController }

    override var shouldAutorotate: Bool { selectedViewController?.shouldAutorotate ?? true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        selectedViewController?.supportedInterfaceOrientations ?? .all
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        selectedViewController?.preferredInterfaceOrientationForPresentation ?? .portrait
    }

    // MARK: - Setup UI
    private func setupUI() {
        view.backgroundColor = .systemBackground

        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        dockTabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dockTabBar)

        tabBarBottomConstraint = dockTabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        tabBarHeightConstraint = dockTabBar.heightAnchor.constraint(equalToConstant: baseTabBarHeight)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            dockTabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dockTabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarBottomConstraint,
            tabBarHeightConstraint
        ])

        updateTabBarLayoutMetrics()
    }
    
    private func setupNotifications() {
        // Слухаємо зміни trait collection для адаптації
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleContentSizeCategoryChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleContentSizeCategoryChange() {
        reloadTabBarItems()
    }

    private func updateTabBarLayoutMetrics() {
        // Перевіряємо чи constraint вже створено
        guard let heightConstraint = tabBarHeightConstraint else { return }
        
        let systemBottom = max(0, view.safeAreaInsets.bottom - additionalSafeAreaInsets.bottom)
        let desiredTabBarHeight = baseTabBarHeight + systemBottom
        
        if heightConstraint.constant != desiredTabBarHeight {
            heightConstraint.constant = desiredTabBarHeight
        }

        updateAdditionalSafeAreaInsets()
        dockTabBar.setNeedsLayout()
    }

    private func updateAdditionalSafeAreaInsets(force: Bool = false) {
        // Перевіряємо чи constraint вже створено
        guard let heightConstraint = tabBarHeightConstraint else { return }
        
        // Віднімаємо contentInsetOffset щоб контент закінчувався ближче до таббара
        // (компенсація скруглених кутів та центральної кнопки)
        let desiredBottom: CGFloat = (isTabBarHidden || dockTabBar.isHidden) ? 0 : max(0, heightConstraint.constant - contentInsetOffset)

        if !force && abs(additionalSafeAreaInsets.bottom - desiredBottom) < 0.5 { return }
        
        // Встановлюємо ТІЛЬКИ для RootTabBarController
        // Дочірні контролери автоматично успадкують через view hierarchy
        additionalSafeAreaInsets.bottom = desiredBottom
    }

    private func reloadTabBarItems() {
        let items: [DockTabBar.Item] = viewControllers.map { vc in
            let sourceVC: UIViewController = {
                if let nav = vc as? UINavigationController {
                    return nav.viewControllers.first ?? nav
                }
                return vc
            }()

            let tbi = sourceVC.tabBarItem
            let title = tbi?.title ?? sourceVC.title ?? ""
            let image = tbi?.image
            let selectedImage = tbi?.selectedImage
            let badgeValue = tbi?.badgeValue

            return .init(title: title, image: image, selectedImage: selectedImage, badgeValue: badgeValue)
        }

        dockTabBar.setup(items: items)
        dockTabBar.updateSelection(_selectedIndex)
    }
    
    // MARK: - KVO for tabBarItem changes
    private func observeTabBarItems() {
        for (index, vc) in viewControllers.enumerated() {
            let sourceVC: UIViewController = {
                if let nav = vc as? UINavigationController {
                    return nav.viewControllers.first ?? nav
                }
                return vc
            }()
            
            // Спостерігаємо за змінами badgeValue
            let badgeObserver = sourceVC.tabBarItem.observe(\.badgeValue, options: [.new]) { [weak self] item, _ in
                self?.dockTabBar.setBadge(item.badgeValue, at: index)
            }
            tabBarItemObservers.append(badgeObserver)
            
            // Спостерігаємо за змінами title
            let titleObserver = sourceVC.tabBarItem.observe(\.title, options: [.new]) { [weak self] item, _ in
                self?.dockTabBar.updateTitle(item.title ?? "", at: index)
            }
            tabBarItemObservers.append(titleObserver)
            
            // Спостерігаємо за змінами image
            let imageObserver = sourceVC.tabBarItem.observe(\.image, options: [.new]) { [weak self] item, _ in
                self?.dockTabBar.updateImage(item.image, selectedImage: item.selectedImage, at: index)
            }
            tabBarItemObservers.append(imageObserver)
        }
    }
    
    private func clearObservers() {
        tabBarItemObservers.forEach { $0.invalidate() }
        tabBarItemObservers.removeAll()
    }

    private func setupTabBarCallbacks() {
        dockTabBar.onTabSelected = { [weak self] index in
            guard let self else { return }

            // Action tabs (наприклад, Chat як модальне вікно)
            if let action = self.actionTabs[index] {
                let prev = self._selectedIndex
                action()
                self.dockTabBar.updateSelection(prev)
                return
            }

            self.selectTab(at: index, animated: true, userInitiated: true)
        }
    }

    // MARK: - Selection / Switching
    private func selectTab(at index: Int, animated: Bool, userInitiated: Bool) {
        guard index >= 0, index < viewControllers.count else { return }

        let targetVC = viewControllers[index]

        // Делегат: чи можна переключитись?
        if userInitiated {
            if delegate?.tabBarController(self, shouldSelect: targetVC, at: index) == false {
                dockTabBar.updateSelection(_selectedIndex)
                return
            }
        }

        // Reselect: повторне натискання на вже вибрану вкладку
        if selectedViewController === targetVC {
            handleReselection(of: targetVC, at: index)
            return
        }

        let fromVC = selectedViewController
        let toVC = targetVC

        _selectedIndex = index
        selectedViewController = toVC
        dockTabBar.updateSelection(index)
        updateCenterButtonState(animated: true)

        if fromVC == nil {
            embed(toVC)
            updateCenterButtonState(animated: false)
            delegate?.tabBarController(self, didSelect: toVC, at: index)
            setNeedsStatusBarAppearanceUpdate()
            return
        }

        // Перевіряємо чи є кастомна анімація від делегата
        if let customAnimator = delegate?.tabBarController(self, animationControllerForTransitionFrom: fromVC!, to: toVC) {
            performCustomTransition(from: fromVC!, to: toVC, animator: customAnimator) { [weak self] in
                guard let self else { return }
                self.delegate?.tabBarController(self, didSelect: toVC, at: index)
                self.setNeedsStatusBarAppearanceUpdate()
            }
        } else {
            transition(from: fromVC!, to: toVC, animated: animated) { [weak self] in
                guard let self else { return }
                self.delegate?.tabBarController(self, didSelect: toVC, at: index)
                self.setNeedsStatusBarAppearanceUpdate()
            }
        }
    }
    
    private func handleReselection(of viewController: UIViewController, at index: Int) {
        _selectedIndex = index
        dockTabBar.updateSelection(index)
        
        // Pop to root для NavigationController
        if popsToRootOnReselect, let nav = viewController as? UINavigationController {
            if nav.viewControllers.count > 1 {
                nav.popToRootViewController(animated: true)
            } else if scrollsToTopOnReselect {
                scrollToTop(in: nav.topViewController)
            }
        } else if scrollsToTopOnReselect {
            scrollToTop(in: viewController)
        }
        
        delegate?.tabBarController(self, didReselect: viewController, at: index)
    }
    
    private func scrollToTop(in viewController: UIViewController?) {
        guard let vc = viewController else { return }
        
        // Знаходимо ScrollView
        if let scrollView = findScrollView(in: vc.view) {
            let topInset = scrollView.adjustedContentInset.top
            scrollView.setContentOffset(CGPoint(x: 0, y: -topInset), animated: true)
        }
    }
    
    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }
        return nil
    }

    private func embed(_ vc: UIViewController) {
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(vc.view)

        NSLayoutConstraint.activate([
            vc.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            vc.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            vc.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    private func transition(from fromVC: UIViewController,
                            to toVC: UIViewController,
                            animated: Bool,
                            completion: @escaping () -> Void) {

        toVC.view.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(toVC.view)
        
        NSLayoutConstraint.activate([
            toVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
            toVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        let finish = {
            fromVC.view.removeFromSuperview()
            completion()
        }

        guard animated else {
            finish()
            return
        }

        switch transitionStyle {
        case .none:
            finish()
            
        case .crossDissolve:
            toVC.view.alpha = 0
            UIView.animate(withDuration: transitionDuration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: {
                toVC.view.alpha = 1
                fromVC.view.alpha = 0
            }, completion: { _ in
                fromVC.view.alpha = 1
                finish()
            })
            
        case .slide:
            let fromIndex = viewControllers.firstIndex(of: fromVC) ?? 0
            let toIndex = viewControllers.firstIndex(of: toVC) ?? 0
            let direction: CGFloat = toIndex > fromIndex ? 1 : -1
            
            toVC.view.transform = CGAffineTransform(translationX: containerView.bounds.width * direction, y: 0)
            
            UIView.animate(withDuration: transitionDuration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState], animations: {
                toVC.view.transform = .identity
                fromVC.view.transform = CGAffineTransform(translationX: -self.containerView.bounds.width * direction, y: 0)
            }, completion: { _ in
                fromVC.view.transform = .identity
                finish()
            })
            
        case .custom:
            // Використовується кастомний аніматор через делегат
            finish()
        }
    }
    
    private func performCustomTransition(from fromVC: UIViewController,
                                         to toVC: UIViewController,
                                         animator: UIViewControllerAnimatedTransitioning,
                                         completion: @escaping () -> Void) {
        let context = TabBarTransitionContext(from: fromVC, to: toVC, containerView: containerView)
        context.completionBlock = { [weak fromVC] didComplete in
            if didComplete {
                fromVC?.view.removeFromSuperview()
            }
            completion()
        }
        
        animator.animateTransition(using: context)
    }

    private func removeAllChildren() {
        selectedViewController?.view.removeFromSuperview()
        selectedViewController = nil

        for vc in children {
            vc.willMove(toParent: nil)
            vc.view.removeFromSuperview()
            vc.removeFromParent()
        }
    }
}

// MARK: - State Restoration
extension RootTabBarController {
    
    static let selectedIndexRestorationKey = "RootTabBarController.selectedIndex"
    
    override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(_selectedIndex, forKey: Self.selectedIndexRestorationKey)
    }
    
    override func decodeRestorableState(with coder: NSCoder) {
        super.decodeRestorableState(with: coder)
        let restoredIndex = coder.decodeInteger(forKey: Self.selectedIndexRestorationKey)
        if restoredIndex >= 0 && restoredIndex < viewControllers.count {
            _selectedIndex = restoredIndex
            selectTab(at: restoredIndex, animated: false, userInitiated: false)
        }
    }
}

// MARK: - Hide

extension RootTabBarController {

    func setTabBarHidden(_ hidden: Bool, animated: Bool = true) {
        setTabBar(hidden: hidden, animated: animated)
    }
}


// MARK: - RootTabBarController Extension
extension RootTabBarController {
    
    private static var menuKey: UInt8 = 0
    private static var isMenuOpenKey: UInt8 = 0
    
    private var centerMenu: CenterButtonMenu? {
        get { objc_getAssociatedObject(self, &Self.menuKey) as? CenterButtonMenu }
        set { objc_setAssociatedObject(self, &Self.menuKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    private var isMenuOpen: Bool {
        get { (objc_getAssociatedObject(self, &Self.isMenuOpenKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Self.isMenuOpenKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
    
    /// Налаштувати меню центральної кнопки
    func setupCenterButtonMenu(actions: [CenterMenuAction], accentColor: UIColor = .systemRed) {
        let menu = CenterButtonMenu()
        menu.configure(actions: actions)
        menu.accentColor = accentColor
        
        menu.onDismiss = { [weak self] in
            self?.isMenuOpen = false
            self?.dockTabBar.setCenterButtonToClose(false)
        }
        
        centerMenu = menu
        
        // Встановлюємо обробник для центральної кнопки
        dockTabBar.onCenterButtonTapped = { [weak self] in
            self?.toggleCenterMenu()
        }
    }
    
    /// Перемикач меню
    func toggleCenterMenu() {
        if isMenuOpen {
            closeCenterMenu()
        } else {
            openCenterMenu()
        }
    }
    
    /// Відкрити меню
    func openCenterMenu() {
        guard let menu = centerMenu, !isMenuOpen else { return }
        guard dockTabBar.centerButton.isEnabled else { return }

        isMenuOpen = true
        dockTabBar.setCenterButtonToClose(true)
        menu.show(in: view, above: dockTabBar)
    }
    
    /// Закрити меню
    func closeCenterMenu() {
        guard isMenuOpen else { return }
        
        centerMenu?.dismiss()
        // isMenuOpen буде скинуто в onDismiss
    }
    
    private func updateCenterButtonState(animated: Bool) {
        let shouldDisable = centerButtonDisabledTabs.contains(_selectedIndex)

        // якщо меню відкрите і ми йдемо на вкладку де кнопку треба вимкнути — закриваємо меню
        if shouldDisable {
            closeCenterMenu()
            dockTabBar.setCenterButtonToClose(false, animated: animated)
        }

        dockTabBar.setCenterButtonEnabled(!shouldDisable, animated: animated)
    }
}

// MARK: - Custom Transition Context
private class TabBarTransitionContext: NSObject, UIViewControllerContextTransitioning {
    
    let containerView: UIView
    var completionBlock: ((Bool) -> Void)?
    
    private let fromVC: UIViewController
    private let toVC: UIViewController
    let isAnimated = true
    private var isCancelled = false
    
    var isInteractive: Bool { false }
    var transitionWasCancelled: Bool { isCancelled }
    var presentationStyle: UIModalPresentationStyle { .none }
    var targetTransform: CGAffineTransform { .identity }
    
    init(from: UIViewController, to: UIViewController, containerView: UIView) {
        self.fromVC = from
        self.toVC = to
        self.containerView = containerView
        super.init()
    }
    
    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
        switch key {
        case .from: return fromVC
        case .to: return toVC
        default: return nil
        }
    }
    
    func view(forKey key: UITransitionContextViewKey) -> UIView? {
        switch key {
        case .from: return fromVC.view
        case .to: return toVC.view
        default: return nil
        }
    }
    
    func initialFrame(for vc: UIViewController) -> CGRect {
        return containerView.bounds
    }
    
    func finalFrame(for vc: UIViewController) -> CGRect {
        return containerView.bounds
    }
    
    func completeTransition(_ didComplete: Bool) {
        completionBlock?(didComplete)
    }
    
    func updateInteractiveTransition(_ percentComplete: CGFloat) {}
    func finishInteractiveTransition() {}
    func cancelInteractiveTransition() { isCancelled = true }
    func pauseInteractiveTransition() {}
}

// MARK: - Tab Item Control
final class TabItemControl: UIControl {
    
    var spacing: CGFloat = 2 { didSet { spacingConstraint?.constant = spacing } }
    var selectedColor: UIColor = .systemBlue { didSet { applyColors() } }
    var unselectedColor: UIColor = .gray { didSet { applyColors() } }
    
    override var isSelected: Bool { didSet { applyColors() } }
    override var isEnabled: Bool  { didSet { applyColors() } }
    
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let badgeView = BadgeView()
    
    private var normalImage: UIImage?
    private var selectedImage: UIImage?
    
    var contentInsets = UIEdgeInsets(top: 8, left: 10, bottom: 12, right: 10) {
        didSet { updateInsetConstraints() }
    }
    
    private var spacingConstraint: NSLayoutConstraint?
    private var topConstraint: NSLayoutConstraint?
    private var leftConstraint: NSLayoutConstraint?
    private var rightConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?
    
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
        clipsToBounds = false
        
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .vertical)
        iconView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        titleLabel.font = UIFont(name: "Onest-Medium", size: 12) ?? .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.lineBreakMode = .byTruncatingTail
        
        addSubview(iconView)
        addSubview(titleLabel)
        addSubview(badgeView)
        
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        
        topConstraint = iconView.topAnchor.constraint(equalTo: topAnchor, constant: contentInsets.top)
        leftConstraint = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInsets.left)
        rightConstraint = titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInsets.right)
        spacingConstraint = titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: spacing)
        bottomConstraint = titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -contentInsets.bottom)
        
        NSLayoutConstraint.activate([
            topConstraint!,
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            spacingConstraint!,
            leftConstraint!, rightConstraint!, bottomConstraint!,
            
            // Badge position
            badgeView.centerXAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 2),
            badgeView.centerYAnchor.constraint(equalTo: iconView.topAnchor, constant: 2)
        ])
        
        addTarget(self, action: #selector(tapHaptic), for: .touchUpInside)
        applyColors()
    }
    
    private func updateInsetConstraints() {
        topConstraint?.constant = contentInsets.top
        leftConstraint?.constant = contentInsets.left
        rightConstraint?.constant = -contentInsets.right
        bottomConstraint?.constant = -contentInsets.bottom
        setNeedsLayout()
    }
    
    func configure(title: String, image: UIImage?, selectedImage: UIImage?, badgeValue: String? = nil) {
        self.normalImage = image
        self.selectedImage = selectedImage
        
        titleLabel.text = title
        accessibilityLabel = title
        
        iconView.image = (image ?? selectedImage)?.withRenderingMode(.alwaysTemplate)
        setBadge(badgeValue)
        applyColors()
    }
    
    func updateTitle(_ title: String) {
        titleLabel.text = title
        accessibilityLabel = title
    }
    
    func updateImage(_ image: UIImage?, selectedImage: UIImage?) {
        self.normalImage = image
        self.selectedImage = selectedImage
        applyColors()
    }
    
    func setBadge(_ value: String?) {
        badgeView.setValue(value)
        
        if let value = value {
            accessibilityValue = "Badge: \(value)"
        } else {
            accessibilityValue = nil
        }
    }
    
    private func applyColors() {
        let active = isSelected && isEnabled
        let tint = active ? selectedColor : unselectedColor
        
        if active, let sel = selectedImage {
            iconView.image = sel.withRenderingMode(.alwaysTemplate)
        } else if let norm = normalImage {
            iconView.image = norm.withRenderingMode(.alwaysTemplate)
        }
        
        iconView.tintColor = tint
        titleLabel.textColor = tint
        alpha = isEnabled ? 1.0 : 0.5
    }
    
    @objc private func tapHaptic() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let minSize = CGSize(width: 96, height: 72)
        var b = bounds
        let w = max(minSize.width, b.width)
        let h = max(minSize.height, b.height)
        let dx = (w - b.width)/2
        let dy = (h - b.height)/2
        b = b.insetBy(dx: -dx, dy: -dy)
        return b.contains(point)
    }
}

// MARK: - Badge View
final class BadgeView: UIView {
    
    private let label = UILabel()
    
    var badgeColor: UIColor = .systemRed {
        didSet { backgroundColor = badgeColor }
    }
    
    var textColor: UIColor = .white {
        didSet { label.textColor = textColor }
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
        backgroundColor = badgeColor
        layer.masksToBounds = true
        isHidden = true
        
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = textColor
        label.textAlignment = .center
        
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            
            widthAnchor.constraint(greaterThanOrEqualTo: heightAnchor)
        ])
    }
    
    func setValue(_ value: String?) {
        if let value = value, !value.isEmpty {
            label.text = value
            isHidden = false
            
            // Анімація появи
            transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5) {
                self.transform = .identity
            }
        } else {
            isHidden = true
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

// MARK: - Dock Tab Bar
final class DockTabBar: UIView {
    
    struct Item {
        let title: String
        let image: UIImage?
        let selectedImage: UIImage?
        var badgeValue: String?
        
        init(title: String, image: UIImage?, selectedImage: UIImage?, badgeValue: String? = nil) {
            self.title = title
            self.image = image
            self.selectedImage = selectedImage
            self.badgeValue = badgeValue
        }
    }
    
    var onTabSelected: ((Int) -> Void)?
    var onCenterButtonTapped: (() -> Void)?
    
    private var controls: [TabItemControl] = []
    internal let centerButton = UIButton()
    private let centerButtonIconView = UIImageView()
    private var shapeLayer: CAShapeLayer?
    
    // Settings
    var centerButtonSize: CGFloat = 68 { didSet { setNeedsLayout(); setNeedsDisplay() } }
    var centerButtonColor: UIColor = .systemBlue {
        didSet {
            centerButton.backgroundColor = centerButtonColor
            applyItemColors()
        }
    }
    var centerButtonImage: UIImage? { didSet { updateCenterButtonImage() } }
    
    /// Розмір зображення центральної кнопки (ширина і висота)
    var centerButtonImageSize: CGFloat = 28 { didSet { updateCenterButtonImage() } }
    
    var tabbarColor: UIColor = .white { didSet { setNeedsDisplay() } }
    var unselectedItemColor: UIColor = .gray { didSet { applyItemColors() } }
    var padding: CGFloat = 5.0 { didSet { setNeedsDisplay() } }
    
    /// Колір бейджів
    var badgeColor: UIColor = .systemRed {
        didSet { controls.forEach { ($0.subviews.compactMap { $0 as? BadgeView }).forEach { $0.badgeColor = badgeColor } } }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = false
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        clipsToBounds = false
    }
    
    func setup(items: [Item]) {
        controls.forEach { $0.removeFromSuperview() }
        controls.removeAll()
        
        for (idx, item) in items.enumerated() {
            let c = TabItemControl()
            c.tag = idx
            c.selectedColor = centerButtonColor
            c.unselectedColor = unselectedItemColor
            c.configure(title: item.title, image: item.image, selectedImage: item.selectedImage, badgeValue: item.badgeValue)
            c.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            addSubview(c)
            controls.append(c)
        }
        
        setupCenterButtonIfNeeded()
        setNeedsLayout()
        setNeedsDisplay()
    }
    
    func updateSelection(_ index: Int) {
        for (i, c) in controls.enumerated() { c.isSelected = (i == index) }
    }
    
    func setBadge(_ value: String?, at index: Int) {
        guard index >= 0, index < controls.count else { return }
        controls[index].setBadge(value)
    }
    
    func updateTitle(_ title: String, at index: Int) {
        guard index >= 0, index < controls.count else { return }
        controls[index].updateTitle(title)
    }
    
    func updateImage(_ image: UIImage?, selectedImage: UIImage?, at index: Int) {
        guard index >= 0, index < controls.count else { return }
        controls[index].updateImage(image, selectedImage: selectedImage)
    }
    
    private func applyItemColors() {
        controls.forEach {
            $0.selectedColor = centerButtonColor
            $0.unselectedColor = unselectedItemColor
        }
    }
    
    private func setupCenterButtonIfNeeded() {
        if centerButton.superview == nil {
            addSubview(centerButton)
        }
        
        centerButton.backgroundColor = centerButtonColor
        centerButton.layer.cornerRadius = centerButtonSize / 2
        
        centerButton.layer.shadowColor = UIColor.black.cgColor
        centerButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        centerButton.layer.shadowRadius = 8
        centerButton.layer.shadowOpacity = 0.2
        
        // Окремий imageView для іконки (щоб можна було обертати)
        if centerButtonIconView.superview == nil {
            centerButtonIconView.contentMode = .scaleAspectFit
            centerButtonIconView.tintColor = .white
            centerButtonIconView.isUserInteractionEnabled = false
            centerButtonIconView.translatesAutoresizingMaskIntoConstraints = false
            centerButton.addSubview(centerButtonIconView)
            
            // Auto Layout - завжди по центру
            NSLayoutConstraint.activate([
                centerButtonIconView.centerXAnchor.constraint(equalTo: centerButton.centerXAnchor),
                centerButtonIconView.centerYAnchor.constraint(equalTo: centerButton.centerYAnchor),
                centerButtonIconView.widthAnchor.constraint(equalToConstant: 32),
                centerButtonIconView.heightAnchor.constraint(equalToConstant: 32)
            ])
        }
        
        updateCenterButtonImage()
        
        centerButton.removeTarget(nil, action: nil, for: .allEvents)
        centerButton.addTarget(self, action: #selector(centerButtonAction), for: .touchUpInside)
    }
    
    private func updateCenterButtonImage() {
        guard let image = centerButtonImage else {
            centerButtonIconView.image = nil
            return
        }
        
        // Для SF Symbols використовуємо SymbolConfiguration
        let config = UIImage.SymbolConfiguration(pointSize: centerButtonImageSize, weight: .semibold)
        let resizedImage = image.withConfiguration(config)
        centerButtonIconView.image = resizedImage.withRenderingMode(.alwaysTemplate)
    }
    
    /// Публічний доступ до imageView для анімацій
    var centerButtonIcon: UIImageView {
        return centerButtonIconView
    }
    
    @objc private func tabTapped(_ sender: TabItemControl) {
        onTabSelected?(sender.tag)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
    
    @objc private func centerButtonAction() {
        onCenterButtonTapped?()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
        let f = CGFloat(centerButtonSize / 2.0) + padding
        let h = bounds.height
        let w = bounds.width
        let halfW = w / 2.0
        let r = CGFloat(18)
        let cornerRadius: CGFloat = 34
        
        let path = UIBezierPath()
        
        path.move(to: CGPoint(x: 0, y: cornerRadius))
        path.addQuadCurve(to: CGPoint(x: cornerRadius, y: 0), controlPoint: CGPoint(x: 0, y: 0))
        
        path.addLine(to: CGPoint(x: halfW - f - (r / 2.0), y: 0))
        
        path.addQuadCurve(to: CGPoint(x: halfW - f, y: (r / 2.0)), controlPoint: CGPoint(x: halfW - f, y: 0))
        path.addArc(withCenter: CGPoint(x: halfW, y: (r / 2.0)), radius: f, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addQuadCurve(to: CGPoint(x: halfW + f + (r / 2.0), y: 0), controlPoint: CGPoint(x: halfW + f, y: 0))
        
        path.addLine(to: CGPoint(x: w - cornerRadius, y: 0))
        path.addQuadCurve(to: CGPoint(x: w, y: cornerRadius), controlPoint: CGPoint(x: w, y: 0))
        
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.close()
        
        return path.cgPath
    }
    
    // MARK: - Layout
    override func layoutSubviews() {
        super.layoutSubviews()

        let w = bounds.width
        let h = bounds.height
        
        let safeBottom: CGFloat = {
            if let window = self.window {
                return window.safeAreaInsets.bottom
            }
            return safeAreaInsets.bottom > 0 ? safeAreaInsets.bottom : 0
        }()

        let total = controls.count
        guard total > 0 else { return }

        let itemHeight: CGFloat = h + 10
        let itemWidth: CGFloat = 88
        let centerY: CGFloat = itemHeight / 2.0 + 8.0
        let dynamicBottomInset: CGFloat = safeBottom + 10

        let cutoutHalf = centerButtonSize / 2.0
        let gapFromCutout: CGFloat = cutoutHalf + 5.0

        let edgePadding: CGFloat = 20.0

        let centerX = w / 2.0
        let leftAreaStart = edgePadding
        let leftAreaEnd = centerX - gapFromCutout
        let rightAreaStart = centerX + gapFromCutout
        let rightAreaEnd = w - edgePadding

        let leftSpace = leftAreaEnd - leftAreaStart
        let rightSpace = rightAreaEnd - rightAreaStart

        let leftCount = total / 2
        let rightCount = total - leftCount

        let edgeInset: CGFloat = 30.0
        let centerInset: CGFloat = 40.0

        for (i, v) in controls.enumerated() {
            v.bounds.size = CGSize(width: itemWidth, height: itemHeight)
            v.contentInsets.bottom = dynamicBottomInset

            var x: CGFloat

            if i < leftCount {
                let effectiveSpace = leftSpace - edgeInset - centerInset
                
                if leftCount == 1 {
                    x = leftAreaStart + edgeInset + effectiveSpace / 2.0
                } else {
                    let step = effectiveSpace / CGFloat(leftCount - 1)
                    x = leftAreaStart + edgeInset + step * CGFloat(i)
                }
            } else {
                let idx = i - leftCount
                let effectiveSpace = rightSpace - centerInset - edgeInset
                
                if rightCount == 1 {
                    x = rightAreaStart + centerInset + effectiveSpace / 2.0
                } else {
                    let step = effectiveSpace / CGFloat(rightCount - 1)
                    x = rightAreaStart + centerInset + step * CGFloat(idx)
                }
            }

            v.center = CGPoint(x: x, y: centerY)
        }

        centerButton.frame = CGRect(
            x: (w - centerButtonSize) / 2.0,
            y: -centerButtonSize / 2.8 - 4.0 + 2.8,
            width: centerButtonSize,
            height: centerButtonSize
        )

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
