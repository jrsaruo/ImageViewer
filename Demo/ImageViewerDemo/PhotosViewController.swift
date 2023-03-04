//
//  PhotosViewController.swift
//  ImageViewerDemo
//
//  Created by Yusaku Nishi on 2023/02/19.
//

import UIKit
import ImageViewer
import Photos
import SwiftyTable

final class PhotosViewController: UIViewController {
    
    private let collectionView: UICollectionView = {
        let layout = UICollectionViewCompositionalLayout { _, layoutEnvironment in
            let columnCount = 3
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .estimated(130)
                ),
                repeatingSubitem: .init(layoutSize: .init(
                    widthDimension: .fractionalWidth(1 / CGFloat(columnCount)),
                    heightDimension: .estimated(130)
                )),
                count: columnCount
            )
            group.interItemSpacing = .fixed(2)
            
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 2
            return section
        }
        
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.register(PhotoCell.self)
        return collectionView
    }()
    
    private lazy var dataSource = UICollectionViewDiffableDataSource<Int, PHAsset>(collectionView: collectionView) { [weak self] collectionView, indexPath, asset in
        guard let self else { return nil }
        let cell = collectionView.dequeueReusableCell(of: PhotoCell.self, for: indexPath)
        cell.configure(with: asset, contentMode: self.preferredContentMode)
        return cell
    }
    
    private let toggleContentModeButton = UIBarButtonItem()
    
    private var preferredContentMode: UIView.ContentMode = .scaleAspectFill
    
    // MARK: - Lifecycle
    
    override func loadView() {
        collectionView.delegate = self
        view = collectionView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setUpViews()
        loadPhotos()
    }
    
    private func setUpViews() {
        title = "Photos"
        
        // Navigation
        navigationItem.backButtonDisplayMode = .minimal
        
        toggleContentModeButton.primaryAction = UIAction(image: .init(systemName: "rectangle.arrowtriangle.2.inward")) { [weak self] _ in
            self?.toggleContentMode()
        }
        navigationItem.rightBarButtonItem = toggleContentModeButton
    }
    
    private func loadPhotos() {
        let result = PHAsset.fetchAssets(with: .image, options: nil)
        let assets = result.objects(at: IndexSet(integersIn: 0 ..< result.count))
        
        var snapshot = dataSource.snapshot()
        snapshot.appendSections([0])
        snapshot.appendItems(assets)
        dataSource.apply(snapshot, animatingDifferences: false)
        
        if let lastAsset = result.lastObject {
            collectionView.isHidden = true
            Task {
                collectionView.scrollToItem(at: dataSource.indexPath(for: lastAsset)!,
                                            at: .bottom,
                                            animated: false)
                collectionView.isHidden = false
            }
        }
    }
    
    // MARK: - Methods
    
    private func toggleContentMode() {
        let newContentMode: UIView.ContentMode
        let systemImageName: String
        if preferredContentMode == .scaleAspectFill {
            newContentMode = .scaleAspectFit
            systemImageName = "rectangle.arrowtriangle.2.outward"
        } else {
            newContentMode = .scaleAspectFill
            systemImageName = "rectangle.arrowtriangle.2.inward"
        }
        preferredContentMode = newContentMode
        toggleContentModeButton.image = .init(systemName: systemImageName)
        
        var snapshot = dataSource.snapshot()
        let visibleItems = dataSource.snapshot(for: 0).visibleItems
        snapshot.reloadItems(visibleItems)
        dataSource.apply(snapshot)
    }
}

// MARK: - UICollectionViewDelegate -

extension PhotosViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let imageViewer = ImageViewerViewController(page: indexPath.item, dataSource: self)
        navigationController?.delegate = imageViewer
        navigationController?.pushViewController(imageViewer, animated: true)
    }
}

// MARK: - ImageViewerDataSource -

extension PhotosViewController: ImageViewerDataSource {
    
    func numberOfImages(in imageViewer: ImageViewerViewController) -> Int {
        dataSource.snapshot().numberOfItems
    }
    
    func imageViewer(_ imageViewer: ImageViewerViewController,
                     imageSourceAtPage page: Int) -> ImageSource {
        .async(transition: .fade(duration: 0.2)) { [weak self] in
            guard let self else { return nil }
            return await withCheckedContinuation { continuation in
                let asset = self.dataSource.snapshot().itemIdentifiers[page]
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                options.resizeMode = .none
                options.isNetworkAccessAllowed = true
                PHImageManager.default()
                    .requestImage(for: asset,
                                  targetSize: .zero,
                                  contentMode: .aspectFit,
                                  options: options) { image, _ in
                        continuation.resume(returning: image)
                    }
            }
        }
    }
    
    func thumbnailView(forCurrentPageOf imageViewer: ImageViewerViewController) -> UIImageView? {
        let currentPage = imageViewer.currentPage
        let indexPathForCurrentImage = IndexPath(item: currentPage, section: 0)
        guard let cellForCurrentImage = collectionView.cellForItem(at: indexPathForCurrentImage) as? PhotoCell else {
            return nil
        }
        return cellForCurrentImage.imageView
    }
}
