//
//  ViewController.swift
//  vipl
//
//  Created by Steve H. Jung on 12/5/22.
//

import UIKit
import AVKit
import MobileCoreServices
import PhotosUI

class ViewController: UIViewController, PHPickerViewControllerDelegate,   UIDocumentPickerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    var imagePicker: UIImagePickerController?
    var documentPicker: UIDocumentPickerViewController?
    var photoPicker: PHPickerViewController?
    
    @IBAction func capture(_ sender: Any) {
        guard let controller = UIStoryboard(name: "CaptureView", bundle: nil).instantiateInitialViewController() as? CaptureViewController else { return }
        controller.loadViewIfNeeded()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
    
    @IBAction func pickDocument(_ sender: Any) {
        if documentPicker == nil {
            documentPicker = UIDocumentPickerViewController(documentTypes: [String(kUTTypeData)], in: .open)
            documentPicker?.delegate = self
        }
        guard let picker = documentPicker else { return }
        self.present(picker, animated: true)
        return
    }
    
    @IBAction func pickPhotos(_ sender: Any) {
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
    
    @IBAction func swingCollection(_ sender: Any) {
        guard let controller = UIStoryboard(name: "CollectionView", bundle: nil).instantiateInitialViewController() as? CollectionViewController else { return }
        controller.loadViewIfNeeded()
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }
}

extension ViewController {
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
                    controller.playUrl(url: url)
                }
            }
        }
    }
}
