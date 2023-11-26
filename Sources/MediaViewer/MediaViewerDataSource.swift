//
//  MediaViewerDataSource.swift
//
//
//  Created by Yusaku Nishi on 2023/11/04.
//

import UIKit

/// The object you use to provide data for an media viewer.
@MainActor
public protocol MediaViewerDataSource: AnyObject {
    
    /// Asks the data source to return the number of media in the media viewer.
    /// - Parameter mediaViewer: An object representing the media viewer requesting this information.
    /// - Returns: The number of media in `mediaViewer`.
    func numberOfMedia(in mediaViewer: MediaViewerViewController) -> Int
    
    /// Asks the data source to return media to view at the particular page in the media viewer.
    /// - Parameters:
    ///   - mediaViewer: An object representing the media viewer requesting this information.
    ///   - page: A page in the media viewer.
    /// - Returns: Media to view on `page` in `mediaViewer`.
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        mediaOnPage page: Int
    ) -> Media
    
    /// Asks the data source to return an aspect ratio of media.
    ///
    /// The ratio will be used to determine a size of page thumbnail.
    /// This method should return immediately.
    ///
    /// - Parameters:
    ///   - mediaViewer: An object representing the media viewer requesting this information.
    ///   - page: A page in the media viewer.
    /// - Returns: An aspect ratio of media on the specified page.
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        mediaWidthToHeightOnPage page: Int
    ) -> CGFloat?
    
    /// Asks the data source to return a source of a thumbnail image on the page control bar in the media viewer.
    /// - Parameters:
    ///   - mediaViewer: An object representing the media viewer requesting this information.
    ///   - page: A page in the media viewer.
    ///   - preferredThumbnailSize: An expected size of the thumbnail image. For better performance, it is preferable to shrink the thumbnail image to a size that fills this size.
    /// - Returns: A source of a thumbnail image on the page control bar in `mediaViewer`.
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        pageThumbnailOnPage page: Int,
        filling preferredThumbnailSize: CGSize
    ) -> Source<UIImage?>
    
    /// Asks the data source to return the transition source view for the current page of the media viewer.
    ///
    /// The media viewer uses this view for push or pop transitions.
    /// On the push transition, an animation runs as the image expands from this view. The reverse happens on the pop.
    ///
    /// If `nil`, the animation looks like cross-dissolve.
    ///
    /// - Parameter mediaViewer: An object representing the media viewer requesting this information.
    /// - Returns: The transition source view for current page of `mediaViewer`.
    func transitionSourceView(
        forCurrentPageOf mediaViewer: MediaViewerViewController
    ) -> UIView?
    
    /// Asks the data source to return the transition source image for the current page of the media viewer.
    ///
    /// The media viewer uses this image for the push transition if needed.
    /// If the viewer has not yet acquired an image asynchronously at the start of the push transition,
    /// the viewer starts a transition animation with this image.
    ///
    /// - Parameters:
    ///   - mediaViewer: An object representing the media viewer requesting this information.
    ///   - sourceView: A transition source view that is returned from `transitionSourceView(forCurrentPageOf:)` method.
    /// - Returns: The transition source image for current page of `mediaViewer`.
    func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        transitionSourceImageWith sourceView: UIView?
    ) -> UIImage?
}

// MARK: - Default implementations -

extension MediaViewerDataSource {
    
    public func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        mediaWidthToHeightOnPage page: Int
    ) -> CGFloat? {
        let media = self.mediaViewer(mediaViewer, mediaOnPage: page)
        switch media {
        case .image(.sync(let image?)) where image.size.height > 0:
            return image.size.width / image.size.height
        case .image(.sync), .image(.async):
            return nil
        }
    }
    
    public func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        pageThumbnailOnPage page: Int,
        filling preferredThumbnailSize: CGSize
    ) -> Source<UIImage?> {
        let media = self.mediaViewer(mediaViewer, mediaOnPage: page)
        switch media {
        case .image(.sync(let image)):
            if #available(iOS 15.0, *) {
                return .sync(
                    image?.preparingThumbnail(of: preferredThumbnailSize) ?? image
                )
            } else {
                return .sync(image)
            }
        case .image(.async(let transition, let imageProvider)):
            return .async(transition: transition) {
                let image = await imageProvider()
                if #available(iOS 15.0, *) {
                    return await image?.byPreparingThumbnail(
                        ofSize: preferredThumbnailSize
                    ) ?? image
                } else {
                    return image
                }
            }
        }
    }
    
    public func mediaViewer(
        _ mediaViewer: MediaViewerViewController,
        transitionSourceImageWith sourceView: UIView?
    ) -> UIImage? {
        switch sourceView {
        case let sourceImageView as UIImageView:
            return sourceImageView.image
        default:
            return nil
        }
    }
}
