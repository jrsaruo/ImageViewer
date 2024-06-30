//
//  MediaViewerPageControlBar.swift
//  
//
//  Created by Yusaku Nishi on 2023/03/18.
//

import UIKit
import Combine

@MainActor
protocol MediaViewerPageControlBarDataSource: AnyObject {
    func mediaViewerPageControlBar(
        _ pageControlBar: MediaViewerPageControlBar,
        thumbnailWith mediaIdentifier: AnyMediaIdentifier,
        filling preferredThumbnailSize: CGSize
    ) -> Source<UIImage?>
    
    func mediaViewerPageControlBar(
        _ pageControlBar: MediaViewerPageControlBar,
        widthToHeightOfThumbnailWith mediaIdentifier: AnyMediaIdentifier
    ) -> CGFloat?
}

final class MediaViewerPageControlBar: UIView {
    
    enum State: Hashable, Sendable {
        case collapsing
        
        /// The collapsed state during scroll.
        /// - Parameters:
        ///   - indexPathForFinalDestinationItem: The index path for where you will eventually arrive after ending dragging.
        case collapsed(indexPathForFinalDestinationItem: IndexPath?)
        
        case expanding
        case expanded
        
        /// The state of interactively transitioning between pages.
        case transitioningInteractively(UICollectionViewTransitionLayout, forwards: Bool)
        
        case reloading
        
        var indexPathForFinalDestinationItem: IndexPath? {
            guard case .collapsed(let indexPath) = self else { return nil }
            return indexPath
        }
    }
    
    enum Layout {
        /// A normal layout.
        case normal(MediaViewerPageControlBarLayout)
        
        /// A layout during interactive paging transition.
        case transition(UICollectionViewTransitionLayout)
    }
    
    private typealias CellRegistration = UICollectionView.CellRegistration<
        PageControlBarThumbnailCell,
        AnyMediaIdentifier
    >
    
    weak var dataSource: (any MediaViewerPageControlBarDataSource)?
    
    private(set) var state: State = .collapsed(indexPathForFinalDestinationItem: nil)
    
    private var indexPathForCurrentCenterItem: IndexPath? {
        collectionView.indexPathForHorizontalCenterItem
    }
    
    private var currentCenterPage: Int? {
        indexPathForCurrentCenterItem?.item
    }
    
    // MARK: Publishers
    
    /// What caused the page change.
    enum PageChangeReason: Hashable {
        case configuration
        case load
        case tapOnPageThumbnail
        case scrollingBar
        case interactivePaging
    }
    
    var pageDidChange: some Publisher<(page: Int, reason: PageChangeReason), Never> {
        _pageDidChange
            .removeDuplicates { $0.page == $1.page }
            .dropFirst() // Initial
    }
    private let _pageDidChange = PassthroughSubject<(page: Int, reason: PageChangeReason), Never>()
    
    // MARK: UI components
    
    private var layout: Layout {
        switch collectionView.collectionViewLayout {
        case let barLayout as MediaViewerPageControlBarLayout:
            return .normal(barLayout)
        case let transitionLayout as UICollectionViewTransitionLayout:
            return .transition(transitionLayout)
        default:
            preconditionFailure(
                "Unknown layout: \(collectionView.collectionViewLayout)"
            )
        }
    }
    
    private lazy var collectionView: UICollectionView = {
        let layout = MediaViewerPageControlBarLayout(style: .collapsed)
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        return collectionView
    }()
    
    lazy var diffableDataSource = UICollectionViewDiffableDataSource<Int, AnyMediaIdentifier>(
        collectionView: collectionView
    ) { [weak self] collectionView, indexPath, mediaIdentifier in
        guard let self else { return nil }
        return collectionView.dequeueConfiguredReusableCell(
            using: cellRegistration,
            for: indexPath,
            item: mediaIdentifier
        )
    }
    
    private lazy var cellRegistration = CellRegistration { [weak self] cell, indexPath, mediaIdentifier in
        guard let self, let dataSource else { return }
        let scale = traitCollection.displayScale
        let preferredSize = CGSize(
            width: cell.bounds.width * scale,
            height: cell.bounds.height * scale
        )
        let thumbnailSource = dataSource.mediaViewerPageControlBar(
            self,
            thumbnailWith: mediaIdentifier,
            filling: preferredSize
        )
        cell.configure(with: thumbnailSource)
    }
    
    // MARK: - Initializers
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpViews()
    }
    
    private func setUpViews() {
        // FIXME: [Workaround] Initialize cellRegistration before applying a snapshot to diffableDataSource.
        _ = cellRegistration
        
        // Subviews
        collectionView.delegate = self
        addSubview(collectionView)
        
        // Layout
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    // MARK: - Override
    
    override var intrinsicContentSize: CGSize {
        CGSize(width: super.intrinsicContentSize.width, height: 42)
    }
    
    // MARK: - Lifecycle
    
    override func layoutSubviews() {
        super.layoutSubviews()
        adjustContentInset()
    }
    
    private func adjustContentInset() {
        guard bounds.width > 0 else { return }
        let offset = (bounds.width - MediaViewerPageControlBarLayout.collapsedItemWidth) / 2
        collectionView.contentInset = .init(
            top: 0,
            left: offset,
            bottom: 0,
            right: offset
        )
    }
    
    // MARK: - Methods
    
    func configure(
        mediaIdentifiers: [AnyMediaIdentifier],
        currentIdentifier: AnyMediaIdentifier
    ) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, AnyMediaIdentifier>()
        snapshot.appendSections([0])
        snapshot.appendItems(mediaIdentifiers)
        
        let currentPage = snapshot.indexOfItem(currentIdentifier)!
        diffableDataSource.apply(snapshot) {
            let indexPath = IndexPath(item: currentPage, section: 0)
            self.expandAndScrollToItem(
                at: indexPath,
                causingBy: .configuration,
                animated: false
            )
        }
    }
    
    /// Loads identifiers for media.
    /// - Parameters:
    ///   - identifiers: Identifiers for media to load.
    ///   - expandingIdentifier: An identifier for media to expand after the loading.
    ///   - animated: Whether to animate the loading.
    ///   - completion: A closure to execute when the loading completes.
    func loadItems(
        _ identifiers: [AnyMediaIdentifier],
        expandingItemWith expandingIdentifier: AnyMediaIdentifier,
        animated: Bool,
        completion: (() -> Void)? = nil
    ) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, AnyMediaIdentifier>()
        snapshot.appendSections([0])
        snapshot.appendItems(identifiers)
        diffableDataSource.apply(snapshot, animatingDifferences: animated)
        
        guard let indexPath = diffableDataSource.indexPath(for: expandingIdentifier) else {
            completion?()
            return
        }
        _pageDidChange.send((page: indexPath.item, reason: .load))
        updateLayout(
            expandingItemAt: indexPath,
            expandingThumbnailWidthToHeight: dataSource?.mediaViewerPageControlBar(
                self,
                widthToHeightOfThumbnailWith: expandingIdentifier
            ),
            animated: animated
        ) { _ in
            completion?()
        }
    }
    
    private func page(with identifier: AnyMediaIdentifier) -> Int? {
        diffableDataSource.snapshot().indexOfItem(identifier)
    }
    
    private func mediaIdentifier(forPage page: Int) -> AnyMediaIdentifier {
        diffableDataSource.snapshot().itemIdentifiers[page]
    }
    
    private func cell(for identifier: AnyMediaIdentifier) -> PageControlBarThumbnailCell? {
        guard let indexPath = diffableDataSource.indexPath(for: identifier),
              let cell = collectionView.cellForItem(at: indexPath) else {
            return nil
        }
        guard let cell = cell as? PageControlBarThumbnailCell else {
            assertionFailure("Unexpected cell: \(cell)")
            return nil
        }
        return cell
    }
    
    private func updateLayout(
        expandingItemAt indexPath: IndexPath?,
        expandingThumbnailWidthToHeight: CGFloat? = nil,
        animated: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        let style: MediaViewerPageControlBarLayout.Style
        if let indexPath {
            style = .expanded(
                indexPath,
                expandingThumbnailWidthToHeight: expandingThumbnailWidthToHeight
            )
        } else {
            style = .collapsed
        }
        let layout = MediaViewerPageControlBarLayout(style: style)
        collectionView.setCollectionViewLayout(
            layout,
            animated: animated,
            completion: completion
        )
    }
    
    /// Expand an item and scroll there.
    /// - Parameters:
    ///   - indexPath: An index path for the expanding item.
    ///   - reason: What causes the page change. If non-nil, the page change will be notified with it.
    ///   - thumbnailWidthToHeight: An aspect ratio of the expanding thumbnail to calculate the size of expanding item.
    ///   - duration: The total duration of the animation.
    ///   - animated: Whether to animate expanding and scrolling.
    private func expandAndScrollToItem(
        at indexPath: IndexPath,
        causingBy reason: PageChangeReason?,
        thumbnailWidthToHeight: CGFloat? = nil,
        duration: CGFloat = 0.5,
        animated: Bool
    ) {
        state = .expanding
        if let reason {
            _pageDidChange.send((page: indexPath.item, reason: reason))
        }
        
        func expandAndScroll() {
            updateLayout(
                expandingItemAt: indexPath,
                expandingThumbnailWidthToHeight: thumbnailWidthToHeight,
                animated: false
            )
            // NOTE: Without this, a thumbnail may shift out of the center after scrolling.
            collectionView.scrollToItem(
                at: indexPath,
                at: .centeredHorizontally,
                animated: false
            )
            state = .expanded
            
            if thumbnailWidthToHeight == nil {
                correctExpandingItemAspectRatioIfNeeded()
            }
        }
        if animated {
            UIViewPropertyAnimator(duration: duration, dampingRatio: 1) {
                expandAndScroll()
            }.startAnimation()
        } else {
            expandAndScroll()
        }
    }
    
    private func correctExpandingItemAspectRatioIfNeeded() {
        guard let indexPathForCurrentCenterItem, let dataSource else { return }
        let page = indexPathForCurrentCenterItem.item
        let identifier = mediaIdentifier(forPage: page)
        
        if let thumbnailWidthToHeight = dataSource.mediaViewerPageControlBar(self, widthToHeightOfThumbnailWith: identifier) {
            expandAndScrollToItem(
                at: indexPathForCurrentCenterItem,
                causingBy: nil,
                thumbnailWidthToHeight: thumbnailWidthToHeight,
                animated: false
            )
            return
        }
        
        let thumbnailSource = dataSource.mediaViewerPageControlBar(
            self,
            thumbnailWith: identifier,
            filling: .init(width: 100, height: 100)
        )
        switch thumbnailSource {
        case .sync(let thumbnail):
            guard let thumbnail, thumbnail.size.height > 0 else { return }
            expandAndScrollToItem(
                at: indexPathForCurrentCenterItem,
                causingBy: nil,
                thumbnailWidthToHeight: thumbnail.size.width / thumbnail.size.height,
                animated: false
            )
        case .async(_, let thumbnailProvider):
            Task {
                guard let thumbnail = await thumbnailProvider(),
                      thumbnail.size.height > 0,
                      state == .expanded,
                      self.indexPathForCurrentCenterItem == indexPathForCurrentCenterItem else { return }
                expandAndScrollToItem(
                    at: indexPathForCurrentCenterItem,
                    causingBy: nil,
                    thumbnailWidthToHeight: thumbnail.size.width / thumbnail.size.height,
                    duration: 0.2,
                    animated: true
                )
            }
        }
    }
    
    private func expandAndScrollToCenterItem(
        animated: Bool,
        causingBy reason: PageChangeReason
    ) {
        guard let indexPathForCurrentCenterItem else { return }
        expandAndScrollToItem(
            at: indexPathForCurrentCenterItem,
            causingBy: reason,
            animated: animated
        )
    }
    
    private func collapseItem() {
        guard case .normal(let barLayout) = layout,
              barLayout.style.indexPathForExpandingItem != nil else { return }
        state = .collapsing
        UIViewPropertyAnimator(duration: 0.5, dampingRatio: 1) {
            self.updateLayout(expandingItemAt: nil, animated: false)
            self.state = .collapsed(indexPathForFinalDestinationItem: nil)
        }.startAnimation()
    }
}

// MARK: - Reloading -

extension MediaViewerPageControlBar {
    
    func startReloading() async {
        let readyStates: [State] = [.expanded, .reloading]
        while !readyStates.contains(state) {
            await Task.yield()
        }
        state = .reloading
    }
    
    func finishReloading() {
        assert(state == .reloading)
        state = .expanded
    }
    
    /// Performs the body of the vanish animation.
    ///
    /// This method itself does not animate, so call it in an animation block.
    /// It also does not update the data source so you have to call
    /// `loadItems(_:expandingItemWith:animated:)` after this animation is finished.
    ///
    /// - Parameter identifiers: Identifiers for media to perform vanish animation.
    func performVanishAnimationBody(
        for identifiers: some Sequence<AnyMediaIdentifier>
    ) {
        assert(state == .reloading)
        
        for identifier in identifiers {
            cell(for: identifier)?.performVanishAnimationBody()
        }
    }
}

// MARK: - Interactive paging -

extension MediaViewerPageControlBar {
    
    func startInteractivePaging(forwards: Bool) {
        guard case .normal(let barLayout) = layout else {
            assertionFailure()
            return
        }
        
        guard let currentCenterPage else { return }
        let destinationPage = currentCenterPage + (forwards ? 1 : -1)
        guard 0 <= destinationPage,
              destinationPage < collectionView.numberOfItems(inSection: 0) else {
            return
        }
        
        let destinationIdentifier = mediaIdentifier(
            forPage: destinationPage
        )
        let expandingThumbnailWidthToHeight = dataSource?.mediaViewerPageControlBar(
            self,
            widthToHeightOfThumbnailWith: destinationIdentifier
        )
        let style: MediaViewerPageControlBarLayout.Style = .expanded(
            IndexPath(item: destinationPage, section: 0),
            expandingThumbnailWidthToHeight: expandingThumbnailWidthToHeight
        )
        let newLayout = MediaViewerPageControlBarLayout(style: style)
        
        /*
         NOTE:
         Using UICollectionView.startInteractiveTransition(to:completion:),
         there is a lag from the end of the transition
         until (completion is called and) the next transition can be started.
         */
        let transitionLayout = UICollectionViewTransitionLayout(
            currentLayout: barLayout,
            nextLayout: newLayout
        )
        collectionView.collectionViewLayout = transitionLayout
        state = .transitioningInteractively(transitionLayout, forwards: forwards)
    }
    
    func updatePagingProgress(_ progress: CGFloat) {
        guard case .transitioningInteractively(let layout, _) = state else {
            return
        }
        layout.transitionProgress = progress
    }
    
    func finishInteractivePaging() {
        guard case .transitioningInteractively(let layout, _) = state else {
            return
        }
        collectionView.collectionViewLayout = layout.nextLayout
        state = .expanded
        
        if let currentCenterPage {
            _pageDidChange.send((page: currentCenterPage, reason: .interactivePaging))
        }
    }
    
    func cancelInteractivePaging() {
        guard case .transitioningInteractively(let layout, _) = state else {
            return
        }
        collectionView.collectionViewLayout = layout.currentLayout
        state = .expanded
    }
}

// MARK: - UICollectionViewDelegate -

extension MediaViewerPageControlBar: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        
        // FIXME: Allow selection during the reloading
        guard state != .reloading else { return }
        
        if case .normal(let barLayout) = layout,
           barLayout.style.indexPathForExpandingItem != indexPath {
            expandAndScrollToItem(
                at: indexPath,
                causingBy: .tapOnPageThumbnail,
                animated: true
            )
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        collapseItem()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        switch state {
        case .collapsed(let indexPathForFinalDestinationItem):
            guard let indexPathForCurrentCenterItem,
                  scrollView.isDragging else { return }
            _pageDidChange.send(
                (page: indexPathForCurrentCenterItem.item, reason: .scrollingBar)
            )
            
            /*
             NOTE:
             Start expanding when the final destination approaches.
             However, if the destination is the first or last item,
             ignore it and wait until the scroll is done because
             the scroll may bounce on the edge.
             */
            if indexPathForCurrentCenterItem == indexPathForFinalDestinationItem,
               !isEdgeIndexPath(indexPathForCurrentCenterItem) {
                expandAndScrollToCenterItem(animated: true, causingBy: .scrollingBar)
            }
        case .collapsing, .expanding, .expanded, .transitioningInteractively, .reloading:
            break
        }
    }
    
    private func isEdgeIndexPath(_ indexPath: IndexPath) -> Bool {
        switch indexPath.item {
        case 0, collectionView.numberOfItems(inSection: 0) - 1:
            return true
        default:
            return false
        }
    }
    
    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        let targetPoint = CGPoint(
            x: targetContentOffset.pointee.x + collectionView.adjustedContentInset.left,
            y: 0
        )
        let targetIndexPath = collectionView.indexPathForItem(at: targetPoint)
        state = .collapsed(
            indexPathForFinalDestinationItem: targetIndexPath
        )
    }
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        /*
         When the finger is released with the finger stopped
         or
         when the finger is released at the point where it exceeds the limit of left and right edges.
         */
        if !scrollView.isDragging {
            guard let indexPath = indexPathForCurrentCenterItem ?? state.indexPathForFinalDestinationItem else {
                return
            }
            expandAndScrollToItem(
                at: indexPath,
                causingBy: .scrollingBar,
                animated: true
            )
        }
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        switch state {
        case .collapsing, .collapsed, .reloading:
            expandAndScrollToCenterItem(animated: true, causingBy: .scrollingBar)
        case .expanding, .expanded, .transitioningInteractively:
            break // NOP
        }
    }
}
