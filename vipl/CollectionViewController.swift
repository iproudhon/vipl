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
import os

// TODO: this is not working properly, need to remove dirUpdated() method below
class FolderMonitor {
    private var fd: Int32?
    private var observer: DispatchSourceFileSystemObject?

    // TODO: error handling or better protocol
    func observe(url: URL, handler: @escaping () -> Void) -> Bool {
        self.fd = open(url.path, O_EVTONLY)
        if self.fd! < 0 {
            return false
        }
        // TODO: need to monitor on other events? [.write, .rename, .delete, .extend] instead of .write
        self.observer = DispatchSource.makeFileSystemObjectSource(fileDescriptor: self.fd!, eventMask: .write , queue: DispatchQueue.main)
        self.observer!.setEventHandler(handler: handler)
        self.observer!.resume()
        return true
    }

    func close() {
        self.observer?.cancel()
        if let fd = self.fd, fd > 0 {
            Darwin.close(fd)
        }
        self.fd = nil
        self.observer = nil
    }
}

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
    var description: String?
    var duration: CMTime?

    init(url: URL?, creationDate: Date?, meta: String?, dimensions: CGSize?, thumbnail: UIImage?, description: String?, duration: CMTime?) {
        self.url = url
        self.creationDate = creationDate
        self.meta = meta
        self.dimensions = dimensions
        self.thumbnail = thumbnail
        self.description = description
        self.duration = duration
    }

    func has(tags: [String]?) -> Bool {
        guard let tags = tags else { return true }
        if tags.count == 0 {
            return true
        }
        guard let desc = self.description?.lowercased() else { return false }
        return tags.contains { tag in
            desc.contains(tag.lowercased())
        }
    }
}

class CollectionViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, PHPickerViewControllerDelegate, UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate {
    
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var flowLayout: UICollectionViewFlowLayout!
    
    @IBOutlet weak var menuButton: UIButton!
    @IBOutlet weak var searchButton: UIButton!
    @IBOutlet weak var captureButton: UIButton!
    @IBOutlet weak var textField: UITextField!
    
    private let refreshControl = UIRefreshControl()
    
    private var numberOfCellsPerRow = 3
    private var interspace = 2

    private var dirMonitor: FolderMonitor?
    private var swingItems: [SwingItem]?
    private var filteredItems: [SwingItem]?
    private var dirModifiedTime: Date?

    private var tags: [String] = []

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
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.setupLayout()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        DispatchQueue.main.async {
            self.collectionView.reloadData()
            if self.dirUpdated() {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.loadVideos()
                }
            }
            self.monitorDir()

            // initialize ml models
            DispatchQueue.global(qos: .utility).async {
                Poser().updateModel()
                _ = DeepLab()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.dirMonitor?.close()
        self.dirMonitor = nil
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.numberOfCellsPerRow = size.width <= size.height ? 3 : 6
        self.setupLayout()
    }

    func setupLayout() {
        // textField, searchButton, menuButton
        // collectionView
        // captureButton
        let rect = CGRect(x: view.safeAreaInsets.left,
                          y: view.safeAreaInsets.top,
                          width: view.bounds.width - (view.safeAreaInsets.left + view.safeAreaInsets.right),
                          height: view.bounds.height - (view.safeAreaInsets.top + view.safeAreaInsets.bottom))
        let buttonSize = 34, captureButtonSize = 60
        var x, y: CGFloat

        x = rect.minX
        y = rect.minY
        self.textField.frame = CGRect(x: x, y: y, width: rect.width - CGFloat(2 * buttonSize), height: self.textField.frame.height)
        x += self.textField.frame.width
        self.textField.delegate = self

        self.searchButton.frame = CGRect(x: x, y: y, width: CGFloat(buttonSize), height: CGFloat(buttonSize))
        x += self.searchButton.frame.width

        self.menuButton.frame = CGRect(x: x, y: y, width: CGFloat(buttonSize), height: CGFloat(buttonSize))
        x += self.menuButton.frame.width

        x = rect.minX
        y = rect.minY + self.textField.frame.height
        let height = rect.height - self.textField.frame.height + view.safeAreaInsets.bottom
        self.collectionView.frame = CGRect(x: x, y: y, width: rect.width, height: height)

        x = rect.maxX + view.safeAreaInsets.right - CGFloat(captureButtonSize) * 3 / 2
        y = rect.maxY + view.safeAreaInsets.bottom - CGFloat(captureButtonSize) * 3 / 2
        self.captureButton.frame = CGRect(x: x, y: y, width: CGFloat(captureButtonSize), height: CGFloat(captureButtonSize))

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
            DispatchQueue.global(qos: .userInitiated).async {
                self.loadVideos()
            }
            self.refreshControl.endRefreshing()
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let totalwidth = collectionView.bounds.size.width;
        let interspace = Double(numberOfCellsPerRow - 1) * Double(flowLayout.minimumInteritemSpacing)
        let width = CGFloat(Int(totalwidth - interspace) / numberOfCellsPerRow)
        var height = width
        if let dims = filteredItems?[indexPath[1]].dimensions {
            height = dims.height * width / dims.width
        }
        return CGSizeMake(width, height)
    }

    @IBAction func applyTags(_ sender: Any) {
        self.tags = self.textField.text?.components(separatedBy: " ") ?? []
        if self.tags.count == 1 && self.tags[0].count == 0 {
            self.tags = []
        }
        self.textField.resignFirstResponder()
        self.filteredItems = self.swingItems?.filter { $0.has(tags: self.tags) }
        self.collectionView.reloadData()
    }

    func textFieldShouldReturn(_ sender: UITextField) -> Bool {
        applyTags(sender)
        return false
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

    func dirUpdated() -> Bool {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let savedTime = self.dirModifiedTime ?? Date(timeIntervalSince1970: 0)
        var (_, fileTime) = FileSystemHelper.fileTimes(url: dir)
        if fileTime == nil {
            fileTime = Date(timeIntervalSince1970: 0)
        }
        return fileTime! > savedTime
    }

    func monitorDir() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.dirMonitor = FolderMonitor()
        _ = self.dirMonitor?.observe(url: dir) {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            DispatchQueue.global(qos: .userInitiated).async {
                self.loadVideos()
            }
        }
    }

    func insertItem(item: SwingItem) {
        self.swingItems?.append(item)
        guard item.has(tags: self.tags) else { return }

        func insertionIndex(from: [SwingItem], of element: SwingItem, sortedBy: (SwingItem, SwingItem) -> Bool) -> Int {
            var lo = 0
            var hi = from.count
            while lo < hi {
                let mid = (lo + hi)/2
                if sortedBy(element, from[mid]) {
                    hi = mid
                } else {
                    lo = mid + 1
                }
            }
            return lo
        }
        let index = insertionIndex(from: self.filteredItems!, of: item, sortedBy: {
            $0.creationDate ?? Date() > $1.creationDate ?? Date()
        })
        self.filteredItems?.insert(item, at: index)
        let indexPath = IndexPath(item: index, section: 0)
        self.collectionView.insertItems(at: [indexPath])
    }

    func loadVideos() {
        self.swingItems = []
        self.filteredItems = []

        DispatchQueue.main.async {
            self.collectionView.reloadData()
        }

        do {
            let fileManager = FileManager.default
            let dir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            var (_, modifiedTime) = FileSystemHelper.fileTimes(url: dir)
            if modifiedTime == nil {
                modifiedTime = Date.distantPast
            }

            var items = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            var modifiedTimes: [String:Date] = [:]
            for i in items {
                let (_, mt) = FileSystemHelper.fileTimes(url: dir.appendingPathComponent(i))
                modifiedTimes[i] = mt ?? Date.distantPast
            }
            items.sort {
                modifiedTimes[$0] ?? Date.distantPast > modifiedTimes[$1] ?? Date.distantPast
            }

            for item in items {
                let url = dir.appendingPathComponent(item)
                let ext = url.pathExtension
                let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)
                if UTTypeConformsTo((uti?.takeRetainedValue())!, kUTTypeMovie) || ext == "moz" {
                    let swingItem = SwingItem(url: url, creationDate: nil, meta: nil, dimensions: nil, thumbnail: nil, description: nil, duration: nil)
                    CollectionViewController.getSwingInfo(item: swingItem, url: url)
                    if swingItem.creationDate == nil {
                        os_log("invalid movie file: \(url.path)")
                        continue
                    }
                    DispatchQueue.main.async {
                        self.insertItem(item: swingItem)
                    }
                }
            }
            self.dirModifiedTime = modifiedTime
        } catch {
            print("Directory listing failed: \(error)")
        }
    }

    static func getThumbnail(url: URL) -> UIImage? {
        return ThumbnailCache.shared.getThumbnail(for: url)
    }

    static func getSwingInfo(item: SwingItem, url: URL) {
        if url.pathExtension != "moz" {
            let asset = AVAsset(url: url)
            let date = asset.creationDate?.value as? Date
            let track = asset.tracks(withMediaType: .video).first
            var size = CGSize(width: 1, height: 1)
            if let track = track {
                size = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform)
            }
            size.width = abs(size.width)
            size.height = abs(size.height)

            item.dimensions = size
            item.creationDate = date
            item.duration = asset.duration
            for i in asset.metadata {
                if String(i.key as? NSString ?? "") == String(AVMetadataKey.quickTimeMetadataKeyDescription as NSString),
                   let description = i.value as? NSString {
                    item.description = String(description)
                }
            }
        } else {
            let r = PointCloudRecorder()
            if !r.open(url.path, forWrite: false) {
                return
            }
            let (creationDate, _) = FileSystemHelper.fileTimes(url: url)
            item.creationDate = creationDate
            item.duration = CMTime(seconds: r.recordedDuration(), preferredTimescale: 600)
            item.description = url.lastPathComponent

            if let info = r.info(),
               let calibrationInfo = FrameCalibrationInfo.fromJson(data: info) {
                item.dimensions = CGSize(width: calibrationInfo.width, height: calibrationInfo.height)
            }
        }

        return
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
        let url = urls[0]
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
                    controller.load(url: url)
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
        return filteredItems?.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
          withReuseIdentifier: "CollectionViewCell",
          for: indexPath) as? CollectionViewCell
        guard let cell = cell else { return CollectionViewCell() }
        cell.collectionViewController = self
        
        let ix = indexPath[1]
        cell.img.frame.size = cell.frame.size
        cell.img.frame.origin = CGPoint(x: 0, y: 0)
        cell.label.frame = CGRect(x: 0, y: cell.frame.size.height -  cell.label.frame.size.height, width: cell.frame.size.width, height: cell.label.frame.size.height)
        cell.label.isHidden = false
        if ix < (filteredItems?.count ?? 0) {
            cell.label.text = (filteredItems?[ix].duration?.toDurationString(withSubSeconds: true) ?? "") + " " + (filteredItems?[ix].description ?? "")
            cell.swingItem = filteredItems?[ix]
        }
        DispatchQueue.main.async {
            if let swingItem = cell.swingItem, let url = swingItem.url {
                cell.img.image = CollectionViewController.getThumbnail(url: url)
            }
        }
        
        if !cell.tapRegistered {
            cell.tapRegistered = true
            cell.addGestureRecognizer(UITapGestureRecognizer(target: cell, action: #selector(cell.tap(_:))))
        }
        return cell
    }
}
