//
//  UIView+Extension.swift
//  
//
//  Created by Yusaku Nishi on 2023/02/25.
//

import UIKit

extension UIView {

    @backDeployed(before: iOS 16.0)
    final public var anchorPoint: CGPoint {
        get { return layer.anchorPoint }
        set { layer.anchorPoint = newValue }
    }

    /// Update the anchor point while keeping its position fixed.
    /// - Parameter newAnchorPoint: The new anchor point.
    func updateAnchorPointWithoutMoving(_ newAnchorPoint: CGPoint) {
        frame.origin.x += (newAnchorPoint.x - anchorPoint.x) * frame.width
        frame.origin.y += (newAnchorPoint.y - anchorPoint.y) * frame.height
        anchorPoint = newAnchorPoint
    }
    
    func firstSubview<View>(ofType type: View.Type) -> View? where View: UIView {
        for subview in subviews {
            if let view = subview as? View {
                return view
            }
            if let view = subview.firstSubview(ofType: View.self) {
                return view
            }
        }
        return nil
    }
}
