//
//  ImageViewerTransition.swift
//  
//
//  Created by Yusaku Nishi on 2023/02/21.
//

import UIKit

@MainActor
final class ImageViewerTransition: NSObject, UIViewControllerAnimatedTransitioning {
    
    let operation: UINavigationController.Operation
    let sourceImageView: UIImageView?
    
    // MARK: - Initializers
    
    init(operation: UINavigationController.Operation,
         sourceImageView: UIImageView?) {
        self.operation = operation
        self.sourceImageView = sourceImageView
    }
    
    // MARK: - Methods
    
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        switch operation {
        case .push:
            return 0.5
        case .pop:
            return 0.35
        case .none:
            return 0.3
        @unknown default:
            return 0.3
        }
    }
    
    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        switch operation {
        case .push:
            animatePushTransition(using: transitionContext)
        case .pop:
            animatePopTransition(using: transitionContext)
        case .none:
            fatalError("Not implemented.")
        @unknown default:
            fatalError("Not implemented.")
        }
    }
    
    private func animatePushTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let imageViewer = transitionContext.viewController(forKey: .to) as? ImageViewerViewController,
              let imageViewerView = transitionContext.view(forKey: .to)
        else {
            assertionFailure("\(Self.self) works only with the push/pop animation for \(ImageViewerViewController.self).")
            transitionContext.completeTransition(false)
            return
        }
        let containerView = transitionContext.containerView
        containerView.addSubview(imageViewerView)
        
        let tabBar = imageViewer.tabBarController?.tabBar
        
        // Back up
        let sourceImageHiddenBackup = sourceImageView?.isHidden ?? false
        let tabBarSuperviewBackup = tabBar?.superview
        
        // Prepare for transition
        imageViewerView.frame = transitionContext.finalFrame(for: imageViewer)
        for subview in imageViewerView.subviews {
            /*
             * NOTE:
             * Make only subviews transparent because changing imageViewerView.alpha
             * also unexpectedly makes the animated imageView transparent.
             */
            subview.alpha = 0
        }
        imageViewerView.layoutIfNeeded()
        
        let currentPageView = imageViewer.currentPageViewController.imageViewerOnePageView
        let currentPageImageView = currentPageView.imageView
        if currentPageImageView.image == nil, let sourceImageView {
            currentPageView.setImage(sourceImageView.image, with: .none)
        }
        
        let configurationBackup = currentPageImageView.transitioningConfiguration
        let currentPageImageFrameInViewer = imageViewerView.convert(currentPageImageView.frame,
                                                                    from: currentPageImageView)
        if let sourceImageView {
            let sourceImageFrameInViewer = imageViewerView.convert(sourceImageView.frame,
                                                                   from: sourceImageView)
            currentPageView.destroyLayoutConfigurationBeforeTransition()
            currentPageImageView.transitioningConfiguration = sourceImageView.transitioningConfiguration
            currentPageImageView.frame = sourceImageFrameInViewer
        } else {
            currentPageView.destroyLayoutConfigurationBeforeTransition()
            currentPageImageView.frame = currentPageImageFrameInViewer
        }
        currentPageImageView.layer.masksToBounds = true
        imageViewer.insertImageViewForTransition(currentPageImageView)
        sourceImageView?.isHidden = true
        
        if let tabBar {
            containerView.addSubview(tabBar)
        }
        
        // Animation
        let duration = transitionDuration(using: transitionContext)
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 0.7) {
            for subview in imageViewerView.subviews {
                subview.alpha = 1
            }
            currentPageImageView.frame = currentPageImageFrameInViewer
            currentPageImageView.transitioningConfiguration = configurationBackup
            
            // NOTE: Keep following properties during transition for smooth animation
            if let sourceImageView = self.sourceImageView {
                currentPageImageView.contentMode = sourceImageView.contentMode
            }
            currentPageImageView.layer.masksToBounds = true
        }
        animator.addCompletion { position in
            switch position {
            case .end:
                currentPageImageView.transitioningConfiguration = configurationBackup
                currentPageView.restoreLayoutConfigurationAfterTransition()
                self.sourceImageView?.isHidden = sourceImageHiddenBackup
                
                if let tabBar {
                    tabBarSuperviewBackup?.addSubview(tabBar)
                }
                
                transitionContext.completeTransition(true)
            case .start, .current:
                assertionFailure()
                break
            @unknown default:
                transitionContext.completeTransition(false)
            }
        }
        animator.startAnimation()
        
        // Customize the tab bar animation
        if imageViewer.hidesBottomBarWhenPushed,
           let tabBar,
           let defaultTabBarAnimationKeys = tabBar.layer.animationKeys() {
            for animationKey in defaultTabBarAnimationKeys {
                assert(animationKey.starts(with: "position"))
                tabBar.layer.removeAnimation(forKey: animationKey)
            }
            animator.addAnimations {
                tabBar.alpha = 0
            }
        }
    }
    
    private func animatePopTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let imageViewer = transitionContext.viewController(forKey: .from) as? ImageViewerViewController,
              let imageViewerView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to),
              let toVC = transitionContext.viewController(forKey: .to)
        else {
            assertionFailure("\(Self.self) works only with the push/pop animation for \(ImageViewerViewController.self).")
            transitionContext.completeTransition(false)
            return
        }
        let containerView = transitionContext.containerView
        containerView.addSubview(toView)
        containerView.addSubview(imageViewerView)
        
        // Back up
        let sourceImageHiddenBackup = sourceImageView?.isHidden ?? false
        
        // Prepare for transition
        toView.frame = transitionContext.finalFrame(for: toVC)
        toVC.view.layoutIfNeeded()
        
        let currentPageView = imageViewer.currentPageViewController.imageViewerOnePageView
        let currentPageImageView = currentPageView.imageView
        let currentPageImageFrameInViewer = imageViewerView.convert(currentPageImageView.frame,
                                                                    from: currentPageView.scrollView)
        let sourceImageFrameInViewer = sourceImageView.map { sourceView in
            imageViewerView.convert(sourceView.frame, from: sourceView)
        }
        currentPageView.destroyLayoutConfigurationBeforeTransition()
        currentPageImageView.frame = currentPageImageFrameInViewer
        imageViewer.insertImageViewForTransition(currentPageImageView)
        sourceImageView?.isHidden = true
        
        // Animation
        let duration = transitionDuration(using: transitionContext)
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: 1) {
            for subview in imageViewerView.subviews where subview != currentPageImageView {
                subview.alpha = 0
            }
            if let sourceImageFrameInViewer {
                currentPageImageView.frame = sourceImageFrameInViewer
                currentPageImageView.transitioningConfiguration = self.sourceImageView!.transitioningConfiguration
            } else {
                currentPageImageView.alpha = 0
            }
            currentPageImageView.clipsToBounds = true // TODO: Change according to the source configuration
        }
        animator.addCompletion { position in
            switch position {
            case .end:
                currentPageImageView.removeFromSuperview()
                self.sourceImageView?.isHidden = sourceImageHiddenBackup
                transitionContext.completeTransition(true)
            case .start, .current:
                assertionFailure()
                break
            @unknown default:
                transitionContext.completeTransition(false)
            }
        }
        animator.startAnimation()
        
        // Customize the tab bar animation
        if let tabBar = toVC.tabBarController?.tabBar,
           let defaultTabBarAnimationKeys = tabBar.layer.animationKeys() {
            for animationKey in defaultTabBarAnimationKeys {
                assert(animationKey.starts(with: "position"))
                tabBar.layer.removeAnimation(forKey: animationKey)
            }
            if toVC.hidesBottomBarWhenPushed {
                animator.addAnimations {
                    tabBar.alpha = 0
                }
                animator.addCompletion { position in
                    if position == .end {
                        tabBar.alpha = 1
                    }
                }
            } else {
                tabBar.alpha = 0
                animator.addAnimations {
                    tabBar.alpha = 1
                }
            }
        }
    }
}
