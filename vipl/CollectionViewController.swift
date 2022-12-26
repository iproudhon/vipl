//
//  CollectionViewController.swift
//  vipl
//
//  Created by Steve H. Jung on 12/22/22.
//

import Foundation
import MobileCoreServices
import AVKit
import UIKit
import PhotosUI

class CollectionViewCell: UICollectionViewCell {
    @IBOutlet weak var label: UILabel!
    @IBOutlet weak var img: UIImageView!
    var collectionViewController: CollectionViewController?
    var swingItem: SwingItem?
    var tapRegistered = false
    
    @objc func tap(_ sender: UITapGestureRecognizer) {
        guard let url = swingItem?.url, let collectionViewController = collectionViewController else { return }
        guard let controller = UIStoryboard(name: "PlayerView", bundle: nil).instantiateInitialViewController() as? PlayerViewController else { return }
        controller.loadViewIfNeeded()
        controller.modalPresentationStyle = .fullScreen
        controller.url = url
        DispatchQueue.main.async {
            collectionViewController.present(controller, animated: true)
        }
    }
}

class SwingItem {
    var url: URL?
    var creationDate: Date?
    var meta: String?
    var dimensions: CGSize?
    var thumbnail: UIImage?
    
    init(url: URL?, creationDate: Date?, meta: String?, dimensions: CGSize?, thumbnail: UIImage?) {
        self.url = url
        self.creationDate = creationDate
        self.meta = meta
        self.dimensions = dimensions
        self.thumbnail = thumbnail
    }
}

class CollectionViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var flowLayout: UICollectionViewFlowLayout!
    
    @IBOutlet weak var menuButton: UIButton!
    @IBOutlet weak var searchButton: UIButton!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var textField: UITextField!
    
    private let refreshControl = UIRefreshControl()
    
    private var numberOfCellsPerRow = 3
    private var interspace = 2
    
    private var swingItems: [SwingItem]?
    
    // pickers
    private var imagePicker: UIImagePickerController?
    private var documentPicker: UIDocumentPickerViewController?
    private var photoPicker: PHPickerViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupMenu()
        collectionView.dataSource = self
        collectionView.delegate = self
        
        collectionView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refresh(_:)), for: .valueChanged)
        
        swingItems = loadVideos()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // flowLayout.scrollDirection = .horizontal
        flowLayout.minimumLineSpacing = CGFloat(interspace)
        flowLayout.minimumInteritemSpacing = CGFloat(interspace)
        // flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 10)
    }
    
    @IBAction func capture(_ sender: Any) {
        guard let controller = UIStoryboard(name: "CaptureView", bundle: nil).instantiateInitialViewController() as? CaptureViewController else { return }
        controller.loadViewIfNeeded()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
    
    @objc func refresh(_ sender: Any) {
        DispatchQueue.main.async {
            self.swingItems = self.loadVideos()
            self.collectionView.reloadData()
            self.refreshControl.endRefreshing()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let totalwidth = collectionView.bounds.size.width;
        let interspace = Double(numberOfCellsPerRow - 1) * Double(flowLayout.minimumInteritemSpacing)
        let width = CGFloat(Int(totalwidth - interspace) / numberOfCellsPerRow)
        var height = width
        if let dims = swingItems?[indexPath[1]].dimensions {
            height = dims.height * width / dims.width
        }
        return CGSizeMake(width, height)
    }
}

extension CollectionViewController {
    
    func setupMenu() {
        // TODO: select & delete
        var options = [UIAction]()
        var item = UIAction(title: "Open Photos", state: .off, handler: { _ in
            self.pickPhoto()
        })
        options.insert(item, at: 0)
        item = UIAction(title: "Open Files", state: .off, handler: { _ in
            self.pickDocument()
        })
        options.insert(item, at: 0)
        let menu = UIMenu(title: "Swings", children: options)
        
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = menu
    }
    
    func loadVideos() -> [SwingItem] {
        var swingItems: [SwingItem] = []
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            let items = try FileManager.default.contentsOfDirectory(atPath: dir[0].path)
            
            for item in items {
                let url = dir[0].appendingPathComponent(item)
                let ext = url.pathExtension
                let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)
                if UTTypeConformsTo((uti?.takeRetainedValue())!, kUTTypeMovie) {
                    let (creationDate, dimensions) = CollectionViewController.getCreationDateAndDimensions(url: url)
                    let swingItem = SwingItem(url: url, creationDate: creationDate, meta: "", dimensions: dimensions, thumbnail: nil)
                    swingItems.append(swingItem)
                }
            }
            swingItems.sort {
                $0.creationDate! > $1.creationDate!
            }
            return swingItems
        } catch {
            print("Directory listing failed: \(error)")
            return []
        }
    }
    
    static func getThumbnail(url: URL) -> UIImage? {
        let asset = AVAsset(url: url)
        let assetImgGenerate = AVAssetImageGenerator(asset: asset)
        assetImgGenerate.appliesPreferredTrackTransform = true
        let pointOfTime = CMTimeMakeWithSeconds(0.1, preferredTimescale: 600)
        do {
            let img = try assetImgGenerate.copyCGImage(at: pointOfTime, actualTime: nil)
            return UIImage(cgImage: img)
        } catch {
            print("\(error.localizedDescription)")
            return nil
        }
    }

    static func getCreationDateAndDimensions(url: URL) -> (Date?, CGSize?) {
        let asset = AVAsset(url: url)
        let date = asset.creationDate?.value as? Date
        let track = asset.tracks(withMediaType: .video).first
        var size = CGSize(width: 1, height: 1)
        if let track = track {
            size = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform)
        }
        size.width = abs(size.width)
        size.height = abs(size.height)
        return (date, size)
    }
}

extension CollectionViewController {
    private func pickDocument() {
        if documentPicker == nil {
            documentPicker = UIDocumentPickerViewController(documentTypes: [String(kUTTypeData)], in: .open)
            documentPicker?.delegate = self
        }
        guard let picker = documentPicker else { return }
        self.present(picker, animated: true)
    }
    
    private func pickPhoto() {
        // use old image picker for now.
        if false {
            if photoPicker == nil {
                var configuration = PHPickerConfiguration()
                configuration.selectionLimit = 1
                configuration.preferredAssetRepresentationMode = .automatic
                configuration.filter = .any(of: [.videos])
                photoPicker = PHPickerViewController(configuration: configuration)
                photoPicker?.delegate = self
            }
            guard let picker = photoPicker else { return }
            self.present(picker, animated: true)
        } else {
            if imagePicker == nil {
                imagePicker = UIImagePickerController()
                imagePicker?.delegate = self
                imagePicker?.sourceType = .photoLibrary
                imagePicker?.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary) ?? []
                imagePicker?.mediaTypes = [String(kUTTypeMovie)]
                if #available(iOS 11.0, *) {
                    imagePicker?.videoExportPreset = AVAssetExportPresetPassthrough
                }
            }
            guard let picker = imagePicker else { return }
            self.present(picker, animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls[0] as? URL else { return }
        guard let controller = UIStoryboard(name: "PlayerView", bundle: nil).instantiateInitialViewController() as? PlayerViewController else { return }
        controller.loadViewIfNeeded()
        controller.modalPresentationStyle = .fullScreen
        controller.url = url
        present(controller, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        self.dismiss(animated: true, completion: nil)
        guard let url = info[.mediaURL] as? URL else { return }
        guard let controller = UIStoryboard(name: "PlayerView", bundle: nil).instantiateInitialViewController() as? PlayerViewController else { return }
        controller.loadViewIfNeeded()
        controller.modalPresentationStyle = .fullScreen
        controller.url = url
        present(controller, animated: true)
    }
    
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        dismiss(animated: true, completion: nil)
        guard !results.isEmpty else { return }
        guard let controller = UIStoryboard(name: "PlayerView", bundle: nil).instantiateInitialViewController() as? PlayerViewController else { return }
        controller.loadViewIfNeeded()
        controller.modalPresentationStyle = .fullScreen
        controller.url = nil
        self.present(controller, animated: true)

        let item = results[0]
        item.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.item") { (url, error) in
            if error != nil {
                print("error \(error!)");
            } else {
                guard let url = url else { return }
                DispatchQueue.main.async {
                    controller.playUrl(url: url)
                }
            }
        }
    }
}

extension CollectionViewController {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return swingItems?.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
          withReuseIdentifier: "CollectionViewCell",
          for: indexPath) as? CollectionViewCell
        guard let cell = cell else { return CollectionViewCell() }
        cell.collectionViewController = self
        
        let ix = indexPath[1]
        cell.label.isHidden = true
        cell.img.frame.size = cell.frame.size
        cell.img.frame.origin = CGPoint(x: 0, y: 0)
        cell.swingItem = swingItems?[ix]
        DispatchQueue.main.async {
            if let swingItem = cell.swingItem, let url = swingItem.url {
                if swingItem.thumbnail == nil {
                    swingItem.thumbnail = CollectionViewController.getThumbnail(url: url)
                }
                if let thumbnail = swingItem.thumbnail {
                    cell.img.image = thumbnail
                }
            }
        }
        
        if !cell.tapRegistered {
            cell.addGestureRecognizer(UITapGestureRecognizer(target: cell, action: #selector(cell.tap(_:))))
        }
        return cell
    }
}