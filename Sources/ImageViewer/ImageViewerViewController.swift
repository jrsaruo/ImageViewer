//
//  ImageViewerViewController.swift
//  
//
//  Created by Yusaku Nishi on 2023/02/19.
//

import UIKit
import Combine

public protocol ImageViewerDataSource: AnyObject {
    func sourceThumbnailView(for imageViewer: ImageViewerViewController) -> UIImageView?
}

open class ImageViewerViewController: UIViewController {
    
    private var cancellables: Set<AnyCancellable> = []
    
    open weak var dataSource: (any ImageViewerDataSource)?
    
    let imageViewerView: ImageViewerView
    private let imageViewerVM = ImageViewerViewModel()
    
    private weak var navigationControllerDelegateBackup: (any UINavigationControllerDelegate)?
    
    // MARK: - Initializers
    
    public init(image: UIImage) {
        self.imageViewerView = ImageViewerView(image: image)
        super.init(nibName: nil, bundle: nil)
    }
    
    @available(*, unavailable, message: "init(coder:) is not supported.")
    required public init?(coder: NSCoder) {
        guard let imageViewerView = ImageViewerView(coder: coder) else { return nil }
        self.imageViewerView = imageViewerView
        super.init(coder: coder)
    }
    
    deinit {
        navigationController?.delegate = navigationControllerDelegateBackup
    }
    
    // MARK: - Override
    
    open override var prefersStatusBarHidden: Bool {
        true
    }
    
    // MARK: - Lifecycle
    
    open override func loadView() {
        view = imageViewerView
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let navigationController else {
            preconditionFailure("ImageViewerViewController must be embedded in UINavigationController.")
        }
        navigationControllerDelegateBackup = navigationController.delegate
        navigationController.delegate = self
        
        setUpViews()
        setUpSubscriptions()
    }
    
    private func setUpViews() {
        // Subviews
        imageViewerView.singleTapRecognizer.addTarget(self, action: #selector(backgroundTapped))
    }
    
    private func setUpSubscriptions() {
        imageViewerVM.$showsImageOnly
            .sink { [weak self] showsImageOnly in
                guard let self else { return }
                let animator = UIViewPropertyAnimator(duration: UINavigationController.hideShowBarDuration,
                                                      dampingRatio: 1) {
                    self.navigationController?.navigationBar.alpha = showsImageOnly ? 0 : 1
                    self.view.backgroundColor = showsImageOnly ? .black : .systemBackground
                }
                if showsImageOnly {
                    animator.addCompletion { position in
                        if position == .end {
                            self.navigationController?.isNavigationBarHidden = true
                        }
                    }
                } else {
                    self.navigationController?.isNavigationBarHidden = false
                }
                animator.startAnimation()
            }
            .store(in: &cancellables)
    }
    
    private var navigationBarScrollEdgeAppearanceBackup: UINavigationBarAppearance?
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        navigationBarScrollEdgeAppearanceBackup = navigationController?.navigationBar.scrollEdgeAppearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        navigationController?.navigationBar.scrollEdgeAppearance = navigationBarScrollEdgeAppearanceBackup
    }
    
    // MARK: - Actions
    
    @objc
    private func backgroundTapped(recognizer: UITapGestureRecognizer) {
        imageViewerVM.showsImageOnly.toggle()
    }
}

// MARK: - UINavigationControllerDelegate -

extension ImageViewerViewController: UINavigationControllerDelegate {
    
    public func navigationController(_ navigationController: UINavigationController,
                                     animationControllerFor operation: UINavigationController.Operation,
                                     from fromVC: UIViewController,
                                     to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        if let sourceThumbnailView = dataSource?.sourceThumbnailView(for: self) {
            return ImageViewerTransition(operation: operation, sourceThumbnailView: sourceThumbnailView)
        }
        return nil
    }
}
