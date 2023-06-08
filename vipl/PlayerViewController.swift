//
//  PlayerViewController.swift
//  vipl
//
//  Created by Steve H. Jung on 12/12/22.
//

import Foundation
import MobileCoreServices
import AVFoundation
import AVKit
import UIKit
import SceneKit

/*
Menu Cameras             X
  Set Range
  Save
  Save as New

 ---->----|---<----
Start   Current <Speed>End
Audio Repeat < Play > <> Save

 Save -> folder
 Save as New
 
 square.and.arrow.down -> popup (Save | Save as New Clip)
 quotelevel
 volume.2.fill volume.slash.fill
 */

class PlayerViewController: UIViewController, UIImagePickerControllerDelegate, UIDocumentPickerDelegate, UINavigationControllerDelegate, UIScrollViewDelegate {
    
    let player = AVPlayer()
    let playerItemVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA])
    lazy var displayLink: CADisplayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired(link:)))
    var assetId: String?

    // video asset orientation & camera position
    private var orientation: UIDeviceOrientation?
    private var position: AVCaptureDevice.Position?
    private var transform: CGAffineTransform?
    private var reverseTransform: CGAffineTransform?

    @IBOutlet var scrollView: UIScrollView!
    @IBOutlet var playerView: PlayerView!
    @IBOutlet var sceneView: SCNView!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var textLogView: UITextView!
    @IBOutlet weak var frameBackButton: UIButton!
    @IBOutlet weak var frameForwardButton: UIButton!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var repeatButton: UIButton!
    @IBOutlet weak var playSpeedMenu: UIButton!
    @IBOutlet weak var rangeButton: UIButton!
    @IBOutlet weak var menuButton: UIButton!
    @IBOutlet weak var dismissButton: UIButton!
    @IBOutlet weak var overlayView: OverlayView!
    @IBOutlet weak var poseButton: UIButton!
    @IBOutlet weak var soundButton: UIButton!

    // .moz
    @objc private var pointCloudPlayer: PointCloudPlayer?
    
    @objc private let rangeSlider = RangeSlider(frame: .zero)

    // for seek
    private var seekInProgress = false
    private var seekChaseTime = CMTime.zero

    // for panning
    var panPoint: CGPoint?
    var panStartTime: CMTime?


    // for pose data analysis
    var poseCollection: PoseCollection = PoseCollection(size: PoseCollection.defaultMaxCount, minimumScore: 0.3)


    private enum PoseEngine {
        case none, posenet, posenetTf, movenetLightning, movenetThunder
    }
    private var poseEngine: PoseEngine = .movenetLightning
    private var showPose = false

    private var showSegments = false
    private var soundOn = true
    
    @IBAction func dismiss(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
    @IBAction func play_pause(_ sender: Any) {
    }
    
    @IBAction func stepBack(_ sender: Any) {
        if let currentItem = player.currentItem {
            if currentItem.canStepBackward {
                currentItem.step(byCount: -1)
            }
        } else if let pointCloudPlayer = pointCloudPlayer {
            _ = pointCloudPlayer.seek(frame: pointCloudPlayer.frame - 1)
            self.rangeSlider.thumb = pointCloudPlayer.currentTime.seconds
        }
    }
    
    @IBAction func stepForward(_ sender: Any) {
        if let currentItem = player.currentItem {
            if currentItem.canStepBackward {
                currentItem.step(byCount: 1)
            }
        } else if let pointCloudPlayer = pointCloudPlayer {
            _ = pointCloudPlayer.seek(frame: pointCloudPlayer.frame + 1)
            self.rangeSlider.thumb = pointCloudPlayer.currentTime.seconds
        }
    }
    
    @IBAction func onRepeat(_ sender: Any) {
        self.isRepeat = !self.isRepeat
        self.setRepeatButtonImage()
    }
    
    @IBAction func onSpeedChange(_ sender: Any) {
    }
    
    @IBAction func setLowerUpperBounds(_ sender: Any) {
        let lower = Swift.max(self.rangeSlider.min, self.rangeSlider.thumb - CGFloat(1.5))
        let upper = Swift.min(self.rangeSlider.thumb + CGFloat(1.5), self.rangeSlider.max)
        
        self.rangeSlider.lowerBound = lower
        self.rangeSlider.upperBound = upper
        self.setupPlayRange(lower, upper)
    }

    private func setAssetId() {
        if let asset = self.player.currentItem?.asset as? AVURLAsset {
            guard let creationDate = asset.creationDate?.value as? Date else {
                self.assetId = ""
                return
            }
            let v = Int64(creationDate.timeIntervalSince1970 * 1000) * Int64(asset.duration.seconds * 1000)
            self.assetId = "\(asset.url.lastPathComponent):\(v)"
        } else if let pointCloudPlayer = pointCloudPlayer,
                  let creationDate = pointCloudPlayer.creationDate,
                  let url = pointCloudPlayer.url {
            let v = Int64(creationDate.timeIntervalSince1970 * 1000) * Int64(pointCloudPlayer.duration.seconds * 1000)
            self.assetId = "\(url.lastPathComponent ):\(v)"
        } else {
            self.assetId = nil
        }
    }

    @IBAction func save(asNew: Bool) {
        if let url = url,
           !asNew && !FileSystemHelper.isFileInAppDirectory(url: url) {
            // TODO: either disable 'save' or show error dialog
            self.log("Can't save. The file is not on App directory.")
            return
        }

        if let currentItem = self.player.currentItem {
            let url: URL!
            if !asNew {
                url = FileSystemHelper.getPrimaryTemporaryFileName()
            } else {
                url = FileSystemHelper.getNextFileName(ext: FileSystemHelper.mov)
            }
            let timeRange = CMTimeRangeFromTimeToTime(start: CMTime(seconds: Double(rangeSlider.lowerBound), preferredTimescale: 600), end: CMTime(seconds: Double(rangeSlider.upperBound), preferredTimescale: 600))
            let exporter = AVAssetExportSession(asset: currentItem.asset, presetName: AVAssetExportPresetHEVCHighestQuality)

            exporter?.videoComposition = currentItem.videoComposition
            exporter?.metadata = currentItem.asset.metadata
            exporter?.outputURL = url
            exporter?.outputFileType = .mov
            exporter?.timeRange = timeRange
            exporter?.exportAsynchronously(completionHandler: { [weak exporter] in
                DispatchQueue.main.async {
                    if let error = exporter?.error {
                        print("failed \(error.localizedDescription)")
                    } else {
                        if asNew {
                            print("Video saved to \(String(describing: url?.path))")
                        } else {
                            guard let orgUrl = (self.player.currentItem?.asset as? AVURLAsset)?.url else { return }
                            self.player.replaceCurrentItem(with: nil)
                            self.setAssetId()
                            self.poseCollection.clear()

                            do {
                                try FileManager.default.removeItem(at: orgUrl)
                                try FileManager.default.moveItem(at: url, to: orgUrl)
                            } catch {
                                print("Failed to remove existing file: \(error.localizedDescription)")
                                return
                            }
                            self.player.replaceCurrentItem(with: AVPlayerItem(url: orgUrl))
                            self.setAssetId()
                            DispatchQueue.global(qos: .background).async {
                                try? self.poseCollection.load(poser: self.poser1, asset: AVAsset(url: orgUrl))
                            }
                            print("Video saved to \(String(describing: orgUrl.path))")
                        }
                    }
                }
            })
        } else if let pointCloudPlayer = pointCloudPlayer {
            if !asNew {
                // TODO: unsafe for now
                let alert = UIAlertController(title: "Save", message: "Save has a problem for now. Do \"Save New\" instead for 3d captures.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)
                return
            }

            let url: URL!
            if !asNew {
                url = FileSystemHelper.getPrimaryTemporaryFileName()
            } else {
                url = FileSystemHelper.getNextFileName(ext: FileSystemHelper.moz)
            }
            let timeRange = CMTimeRangeFromTimeToTime(start: CMTime(seconds: Double(rangeSlider.lowerBound), preferredTimescale: 600), end: CMTime(seconds: Double(rangeSlider.upperBound), preferredTimescale: 600))
            if !pointCloudPlayer.export(to: url, startTime: timeRange.start, endTime: timeRange.end) {
                log("Failed to save")
            } else if asNew {
                log("File saved to \(url.path)")
            } else {
                guard let orgUrl = pointCloudPlayer.url else { return }
                pointCloudPlayer.close()
                setAssetId()
                do {
                    try FileManager.default.removeItem(at: orgUrl)
                    try FileManager.default.moveItem(at: url, to: orgUrl)
                } catch {
                    log("Failed to remove existing file: \(error.localizedDescription)")
                    return
                }
                load(url: orgUrl)
                log("File save to \(orgUrl.path)")
            }
        }
    }

    private var timeObserverToken: Any?
    private var boundaryTimeObserverToken: Any?
    private var playerItemStatusObserver: NSKeyValueObservation?
    private var playerItemFastForwardObserver: NSKeyValueObservation?
    private var playerItemReverseObserver: NSKeyValueObservation?
    private var playerItemFastReverseObserver: NSKeyValueObservation?
    private var playerTimeControlStatusObserver: NSKeyValueObservation?
    
    private var isRepeat = false
    private var playSpeed = Float(1.0)

    private var poser1 = Poser()
    private var poser2: PoseNet!
    private var deepLab: DeepLab!

    var url: URL?

    func load(url: URL) {
        if !PointCloudRecorder.isMovieFile(url.path) {
            self.sceneView.isHidden = true
            self.playerView.player = player
            self.player.replaceCurrentItem(with: AVPlayerItem(url: url))
            self.setAssetId()
            DispatchQueue.global(qos: .background).async {
                try? self.poseCollection.load(poser: self.poser1, asset: AVAsset(url: url))
            }
            self.setupPlayerObservers()

            if let asset = self.player.currentItem?.asset {
                (self.orientation, self.position, self.transform, self.reverseTransform) = asset.videoOrientation()
            }
            player.playImmediately(atRate: playSpeed)

            DispatchQueue.main.async {
                if let asset = self.player.currentItem?.asset {
                    self.log(asset.info())
                }
            }
        } else {
            self.sceneView.isHidden = false
            initSceneView()
            self.pointCloudPlayer = PointCloudPlayer(view: self.sceneView, url: url)
            self.setupPlayerObservers()
            self.setAssetId()
            // self.pointCloudPlayer?.loadPointClouds(log: self.log)
            _ = self.pointCloudPlayer?.seek(frame: 0)
        }
    }
    
    func loadAndPlayVideo(_ sender: Any) {
        if true {
            let picker = UIImagePickerController()
            picker.delegate = self
            picker.sourceType = .photoLibrary
            picker.mediaTypes = UIImagePickerController.availableMediaTypes(for: .photoLibrary) ?? []
            picker.mediaTypes = [String(kUTTypeMovie)]
            self.present(picker, animated: true)
        } else {
            let docPicker = UIDocumentPickerViewController(documentTypes: [String(kUTTypeData)], in: .import)
            docPicker.delegate = self
            self.present(docPicker, animated: true)
            return
        }
    }
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if !urls[0].isFileURL { return }
        load(url: urls[0])
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: nil)
        guard let url = info[.mediaURL] as? URL else { return }
        load(url: url)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Setting category to AVAudioSessionCategoryPlayback failed.")
        }

        self.soundOn = !UserDefaults.standard.bool(forKey: "mute-sound")
        self.player.isMuted = !self.soundOn
        if self.soundOn {
            self.soundButton.tintColor = nil
            self.soundButton.setImage(UIImage(systemName: "speaker.wave.2.fill"), for: .normal)
        } else {
            self.soundButton.tintColor = .systemGray
            self.soundButton.setImage(UIImage(systemName: "speaker.slash.fill"), for: .normal)
        }

        // initialize the range slider
        view.addSubview(rangeSlider)
        rangeSlider.addTarget(self, action: #selector(rangeSliderValueChanged(_:)),
                              for: .valueChanged)

        // initialize tap & pan gesture recognizers
        self.addGestures()

        self.poseButton.tintColor = .systemGray

        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 10.0
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        DispatchQueue.main.async {
            self.poser1.updateModel()
            self.poser1.logFunc = self.log
            do {
                self.poser2 = try PoseNet()
                self.deepLab = DeepLab()
            } catch {
                fatalError("Failed to load posenet model. \(error.localizedDescription)")
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        setupPlaySpeedMenu()
        setupMainMenu()
        setupRangeMenu()

        if let url = url {
            load(url: url)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        player.pause()
        if let pointCloudPlayer = pointCloudPlayer {
            pointCloudPlayer.close()
        }
        if let timeObserverToken = timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
            self.timeObserverToken = nil
        }
        if let boundaryTimeObserverToken = boundaryTimeObserverToken {
            player.removeTimeObserver(boundaryTimeObserverToken)
            self.boundaryTimeObserverToken = nil
        }
        super.viewWillDisappear(animated)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.setupLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        self.setupLayout()
        self.setPlayerFrameSize()
    }

    private func setPlayerFrameSize() {
        let containerSize = scrollView.frame.size
        var size = player.currentItem?.presentationSize
        if (size?.width ?? 0) == 0 {
            playerView.frame.size = containerSize
            return
        }
        var width = size?.width ?? 1
        var height = size?.height ?? 1
        let r1 = width / height
        let r2 = containerSize.width / containerSize.height

        if r1 >= r2 {    // video is wider than container: by height
            width = containerSize.width
            height = width / r2
        } else {
            height = containerSize.height
            width = height * r2
        }
        var pt = CGPoint(x: width, y: height)
        pt = pt.applying(playerView.transform)
        playerView.frame.size = CGSize(width: pt.x, height: pt.y)
        scrollView.contentSize = playerView.frame.size
    }

    private func setupLayout() {
        // playerView
        //   dismiss button
        //   overlay view
        // rangeSlider
        // pose, repeat, range, speed, left, play, right, time, save
        let rect = CGRect(x: view.safeAreaInsets.left,
                          y: view.safeAreaInsets.top,
                          width: view.bounds.width - (view.safeAreaInsets.left + view.safeAreaInsets.right),
                          height: view.bounds.height - (view.safeAreaInsets.top + view.safeAreaInsets.bottom))
        let buttonWidth = 35, buttonHeight = 35, sliderHeight = 40, sliderMargin = 30, timeLabelWidth = 100
        var x, y: CGFloat

        self.scrollView.frame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - CGFloat(Int(buttonHeight * 3 / 2)) - CGFloat(sliderHeight))
        self.setPlayerFrameSize()

        self.dismissButton.frame.origin = CGPoint(x: rect.minX, y: rect.minY)
        self.menuButton.frame.origin = CGPoint(x: rect.width - self.menuButton.frame.size.width, y: rect.minY)

        let height = CGFloat(200)
        y = self.scrollView.frame.origin.y + self.scrollView.frame.height - height
        self.textLogView.frame = CGRect(x: rect.minX, y: y, width: rect.width, height: height)

        // range slider
        x = rect.minX + CGFloat(sliderMargin)
        y = self.scrollView.frame.origin.y + self.scrollView.frame.size.height + 1
        self.rangeSlider.frame = CGRect(x: x, y: y, width: rect.width - CGFloat(2 * sliderMargin), height: CGFloat(sliderHeight))

        y = rangeSlider.frame.origin.y + rangeSlider.frame.size.height * 4 / 3
        x = rect.minX

        self.timeLabel.frame = CGRect(x: x, y: y, width: CGFloat(timeLabelWidth), height: CGFloat(buttonHeight))
        x += CGFloat(timeLabelWidth)

        self.playSpeedMenu.frame = CGRect(x: x, y: y, width: self.playSpeedMenu.frame.size.width, height: CGFloat(buttonHeight))
        x += self.playSpeedMenu.frame.size.width

        // center buttons
        let width = CGFloat(buttonWidth) * 4 / 3
        x = rect.minX + (rect.width - width * 3) / 2
        self.frameBackButton.frame = CGRect(x: x, y: y, width: width, height: CGFloat(buttonHeight))
        x += self.frameBackButton.frame.size.width

        self.playPauseButton.frame = CGRect(x: x, y: y, width: width, height: CGFloat(buttonHeight))
        x += self.playPauseButton.frame.size.width

        self.frameForwardButton.frame = CGRect(x: x, y: y, width: width, height: CGFloat(buttonHeight))
        x += self.frameForwardButton.frame.size.width

        // right side buttons
        x = rect.minX + rect.width
        self.soundButton.frame = CGRect(x: x - CGFloat(buttonWidth), y: y, width: CGFloat(buttonWidth), height: CGFloat(buttonHeight))
        x -= self.soundButton.frame.size.width

        self.rangeButton.frame = CGRect(x: x - CGFloat(buttonWidth), y: y, width: CGFloat(buttonWidth), height: CGFloat(buttonHeight))
        x -= self.rangeButton.frame.size.width

        self.poseButton.frame = CGRect(x: x - CGFloat(buttonWidth), y: y, width: CGFloat(buttonWidth), height: CGFloat(buttonHeight))
        x -= self.poseButton.frame.size.width

        self.repeatButton.frame = CGRect(x: x - CGFloat(buttonWidth), y: y, width: CGFloat(buttonWidth), height: CGFloat(buttonHeight))
        x -= self.repeatButton.frame.size.width
    }

    func setupPlaySpeedMenu() {
        let doit = {(action: UIAction) in
            guard let rate = Float(action.title) else { return }
            self.playSpeed = rate
            self.player.rate = rate
        }
        var options = [UIAction]()
        for i in ["0.05", "0.1", "0.2", "0.5", "0.75", "1", "1.25", "1.5", "2"] {
            let item = UIAction(title: i, state: .off, handler: doit)
            if i == "1" {
                item.state = .on
            }
            options.insert(item, at: 0)
        }
        let menu = UIMenu(title: "Play Speed", options: .displayInline, children: options)
        playSpeedMenu.menu = menu
        if #available(iOS 15.0, *) {
            playSpeedMenu.changesSelectionAsPrimaryAction = true
        }
        playSpeedMenu.showsMenuAsPrimaryAction = true
    }
    
    func setupMainMenu() {
        var options = [UIAction]()
        var str: String
        str = self.textLogView.isHidden ? "Show Logs" : "Hide Logs"
        options.append(UIAction(title: str, state: .off, handler: {_ in
            self.textLogView.isHidden = !self.textLogView.isHidden
            self.setupMainMenu()
        }))
        str = self.showSegments ? "Hide Segments" : "Show Segments"
        options.append(UIAction(title: str, state: .off, handler: {_ in
            self.showSegments = !self.showSegments
            self.setupMainMenu()
        }))
        options.append(UIAction(title: "Save", state: .off, handler: {_ in
            self.save(asNew: false)
        }))
        options.append(UIAction(title: "Save as New", state: .off, handler: {_ in
            self.save(asNew: true)
        }))
        options.append(UIAction(title: "Delete", state: .off, handler: {_ in
            if let url = self.url {
                try? FileManager.default.removeItem(at: url)
            }
            self.dismiss(animated: true)
        }))
        let menu = UIMenu(title: "vipl", children: options)
        
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = menu
    }

    func setupRangeMenu() {
        func do_range(_ lowerOffset: Double, _ upperOffset: Double) {
            let lower = Swift.max(self.rangeSlider.min, self.rangeSlider.thumb - CGFloat(lowerOffset))
            let upper = Swift.min(self.rangeSlider.thumb + CGFloat(upperOffset), self.rangeSlider.max)
            self.rangeSlider.lowerBound = lower
            self.rangeSlider.upperBound = upper
            self.setupPlayRange(lower, upper)
        }

        var options = [UIAction]()
        options.insert(UIAction(title: "Reset Range", state: .off, handler: { _ in
            self.rangeSlider.lowerBound = self.rangeSlider.min
            self.rangeSlider.upperBound = self.rangeSlider.max
            self.setupPlayRange(self.rangeSlider.min, self.rangeSlider.max)
        }), at: 0)
        options.insert(UIAction(title: "1.75 : 1.5", state: .off, handler: { _ in
            do_range(1.75, 1.5)
        }), at: 0)
        options.insert(UIAction(title: "2.0 : 5.0", state: .off, handler: { _ in
            do_range(2.0, 5.0)
        }), at: 0)
        options.insert(UIAction(title: "0.3 : 0.2", state: .off, handler: { _ in
            do_range(0.3, 0.2)
        }), at: 0)

        func do_poses(_ cmd: String) {
            switch cmd {
            case "reset":
                self.overlayView.resetPoses()
                self.refreshOverlayWithCurrentFrame()
            case "freeze-both", "freeze-pose", "freeze-body":
                // get current image & freeze
                guard let item = self.player.currentItem else { return }
                let currentTime = item.currentTime()
                guard let pixelBuffer = self.getFramePixelBuffer(asset: item.asset, time: currentTime) else { return }
                if cmd == "freeze-both" || cmd == "freeze-pose" {
                    poser1.runModel(assetId: self.assetId!, targetView: self.overlayView, pixelBuffer: pixelBuffer, transform: self.reverseTransform!, time: currentTime, freeze: true) { _ in }
                }
                if cmd == "freeze-both" || cmd == "freeze-body" {
                    deepLab.runModel(assetId: self.assetId!, targetView: self.overlayView, image: pixelBuffer, transform: self.reverseTransform!, time: currentTime, freeze: true)
                }
                break
            default:
                break
            }
        }

        // posenet & foreground extraction
        options.insert(UIAction(title: "Reset Overlay", state: .off, handler: { _ in
            do_poses("reset")
        }), at: 0)
        options.insert(UIAction(title: "Freeze", state: .off, handler: { _ in
            do_poses("freeze-both")
        }), at: 0)
        options.insert(UIAction(title: "Freeze Pose", state: .off, handler: { _ in
            do_poses("freeze-pose")
        }), at: 0)
        options.insert(UIAction(title: "Freeze Body", state: .off, handler: { _ in
            do_poses("freeze-body")
        }), at: 0)

        let menu = UIMenu(title: "Ranges & Overlays", children: options)
        rangeButton.showsMenuAsPrimaryAction = true
        rangeButton.menu = menu
    }

    func setupPlayerObservers() {
        if self.player.currentItem != nil {
            playerTimeControlStatusObserver = player.observe(\AVPlayer.timeControlStatus, options: [.initial, .new]) { [unowned self] _, _ in
                DispatchQueue.main.async {
                    self.setPlayPauseButtonImage()
                    self.setRepeatButtonImage()
                }
            }

            let interval = CMTime(value: 1, timescale: 600)
            timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [unowned self] time in
                let timeEllapsed = CGFloat(time.seconds)
                self.rangeSlider.thumb = CGFloat(timeEllapsed)
                self.timeLabel.text = "\(self.createTimeString(time: Float(self.rangeSlider.lowerBound))) \(self.createTimeString(time: Float(timeEllapsed))) \(self.createTimeString(time: Float(self.rangeSlider.upperBound)))"
                if let currentItem = player.currentItem {
                    let startTime = CMTime(seconds: self.rangeSlider.lowerBound, preferredTimescale: 600)
                    let endTime = CMTime(seconds: self.rangeSlider.upperBound, preferredTimescale: 600)
                    if !self.isRepeat {
                        if timeEllapsed >= self.rangeSlider.upperBound {
                            currentItem.seek(to: endTime, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: nil)
                        }
                    } else {
                        if currentItem.currentTime() == currentItem.duration {
                            currentItem.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
                                if success && self.player.timeControlStatus == .paused {
                                    self.player.playImmediately(atRate: self.playSpeed)
                                }
                            }
                        } else if timeEllapsed >= self.rangeSlider.upperBound {
                            let wasPlaying = self.player.timeControlStatus == .playing
                            if wasPlaying {
                                self.player.pause()
                            }
                            currentItem.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
                                if wasPlaying {
                                    self.player.playImmediately(atRate: self.playSpeed)
                                }
                            }
                        }
                    }
                }
            }

            playerItemFastForwardObserver = player.observe(\AVPlayer.currentItem?.canPlayFastForward, options: [.new, .initial]) { [unowned self] player, _ in
                DispatchQueue.main.async {
                    // self.fastForwardButton.isEnabled = player.currentItem?.canPlayFastForward ?? false
                }
            }

            playerItemReverseObserver = player.observe(\AVPlayer.currentItem?.canPlayReverse, options: [.new, .initial]) { [unowned self] player, _ in
                DispatchQueue.main.async {
                    // self.rewindButton.isEnabled = player.currentItem?.canPlayReverse ?? false
                }
            }

            playerItemFastReverseObserver = player.observe(\AVPlayer.currentItem?.canPlayFastReverse, options: [.new, .initial]) { [unowned self] player, _ in
                DispatchQueue.main.async {
                    // self.rewindButton.isEnabled = player.currentItem?.canPlayFastReverse ?? false
                }
            }

            playerItemStatusObserver = player.observe(\AVPlayer.currentItem?.status, options: [.new, .initial, .old]) { [unowned self] player, _ in
                if let item = player.currentItem {
                    if item.status == .readyToPlay {
                        item.add(self.playerItemVideoOutput)
                        self.displayLink.add(to: .main, forMode: .common)
                        self.setPlayerFrameSize()
                    }
                }
                DispatchQueue.main.async {
                    self.updateUIForPlayerItemStatus()
                }
            }
        } else if let pointCloudPlayer = pointCloudPlayer {
            // playerTimeControlStatusObserver
            playerItemStatusObserver = observe(\.pointCloudPlayer!.status, options: [.initial, .new, .old]) { _, _ in
                DispatchQueue.main.async {
                    self.setPlayPauseButtonImage()
                    self.setRepeatButtonImage()
                    self.updateUIForPlayerItemStatus()
                }
            }
            playerItemFastReverseObserver = observe(\.pointCloudPlayer!.currentTime, options: [.initial, .new, .old]) { _, _ in
                DispatchQueue.main.async {
                    // TODO: more work needed to range slider
                    // self.rangeSlider.thumb = CGFloat(pointCloudPlayer.currentTime.seconds)
                    self.timeLabel.text = "\(self.createTimeString(time: Float(self.rangeSlider.lowerBound))) \(self.createTimeString(time: Float(self.rangeSlider.thumb))) \(self.createTimeString(time: Float(self.rangeSlider.upperBound)))"
                }
            }
        }
    }
    
    @IBAction func togglePlay(_ sender: Any) {
        if player.currentItem != nil {
            switch player.timeControlStatus {
            case .playing:
                player.pause()
            case .paused:
                if let currentItem = player.currentItem {
                    if Int(currentItem.currentTime().seconds * 100) >= Int(rangeSlider.upperBound * 100) {
                        //                if CGFloat(currentItem.currentTime().seconds) >= rangeSlider.upperBound {
                        let startTime = CMTime(seconds: Double(rangeSlider.lowerBound), preferredTimescale: 600)
                        currentItem.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero) { success in
                            if success {
                                self.player.playImmediately(atRate: self.playSpeed)
                            }
                        }
                    } else {
                        self.player.playImmediately(atRate: self.playSpeed)
                    }
                }
            default:
                player.pause()
            }
        }
    }
    
    @IBAction func playBackwards(_ sender: Any) {
        if player.currentItem?.currentTime() == .zero {
            if let itemDuration = player.currentItem?.duration {
                player.currentItem?.seek(to: itemDuration, completionHandler: nil)
            }
        }
        player.rate = max(player.rate - 2.0, -2.0)
    }
    
    @IBAction func playFastForward(_ sender: Any) {
        if player.currentItem?.currentTime() == player.currentItem?.duration {
            player.currentItem?.seek(to: .zero, completionHandler: nil)
        }
        player.rate = min(player.rate + 2.0, 2.0)
    }
    
    func createTimeString(time: Float) -> String {
        var sec = Int(time)
        let min = sec / 60
        let cent = Int((time - Float(sec)) * 100.0)
        sec = sec % 60
        if min > 0 {
            return String(format: "%d:%02d:%02d", min, sec, cent)
        } else {
            return String(format: "%2d:%02d", sec, cent)
        }
    }
    
    func setPlayPauseButtonImage() {
        var img: UIImage?
        switch self.player.timeControlStatus {
        case .playing:
            img = UIImage(systemName: "pause.fill")
        case .paused:
            img = UIImage(systemName: "play.fill")
        default:
            img = UIImage(systemName: "pause.fill")
        }
        guard let img = img else { return }
        self.playPauseButton.setImage(img, for: .normal)
    }
    
    func setRepeatButtonImage() {
        self.repeatButton.tintColor = self.isRepeat ? nil : .systemGray
    }
    
    func updateUIForPlayerItemStatus() {
        if let currentItem = player.currentItem {
            switch currentItem.status {
            case .failed:
                playPauseButton.isEnabled = false
                frameBackButton.isEnabled = false
                frameForwardButton.isEnabled = false
                rangeSlider.isEnabled = false
                timeLabel.isEnabled = false
            case .readyToPlay:
                playPauseButton.isEnabled = true
                frameBackButton.isEnabled = true
                frameForwardButton.isEnabled = true
                rangeSlider.isEnabled = true
                timeLabel.isEnabled = true
                let newDurationSeconds = CGFloat(currentItem.duration.seconds)
                let currentTime = CGFloat(CMTimeGetSeconds(player.currentTime()))
                rangeSlider.min = CGFloat(0)
                rangeSlider.max = CGFloat(newDurationSeconds)
                rangeSlider.lowerBound = rangeSlider.min
                rangeSlider.upperBound = rangeSlider.max
                rangeSlider.thumb = CGFloat(currentTime)
                timeLabel.text = createTimeString(time: Float(currentTime))
            default:
                playPauseButton.isEnabled = false
                frameBackButton.isEnabled = false
                frameForwardButton.isEnabled = false
                rangeSlider.isEnabled = false
                timeLabel.isEnabled = false
            }
        } else if let pointCloudPlayer = pointCloudPlayer {
            switch pointCloudPlayer.status {
            case .stopped, .playing:
                playPauseButton.isEnabled = true
                frameBackButton.isEnabled = true
                frameForwardButton.isEnabled = true
                rangeSlider.isEnabled = true
                timeLabel.isEnabled = true
                let newDurationSeconds = CGFloat(pointCloudPlayer.duration.seconds)
                let currentTime = CGFloat(CMTimeGetSeconds(pointCloudPlayer.currentTime))
                rangeSlider.min = CGFloat(0)
                rangeSlider.max = CGFloat(newDurationSeconds)
                rangeSlider.lowerBound = rangeSlider.min
                rangeSlider.upperBound = rangeSlider.max
                rangeSlider.thumb = CGFloat(currentTime)
                timeLabel.text = "\(self.createTimeString(time: Float(self.rangeSlider.lowerBound))) \(self.createTimeString(time: Float(pointCloudPlayer.currentTime.seconds))) \(self.createTimeString(time: Float(self.rangeSlider.upperBound)))"
            default:
                playPauseButton.isEnabled = false
                frameBackButton.isEnabled = false
                frameForwardButton.isEnabled = false
                rangeSlider.isEnabled = false
                timeLabel.isEnabled = false
            }
        }
    }

    @IBAction func toggleShowPose(_ sender: Any) {
        self.showPose = !self.showPose
        self.poseButton.tintColor = self.showPose ? nil : .systemGray
        self.refreshOverlayWithCurrentFrame()
    }

    @IBAction func toggleSound(_ sender: Any) {
        self.soundOn = !self.soundOn
        UserDefaults.standard.setValue(!self.soundOn, forKey: "mute-sound")
        self.player.isMuted = !self.soundOn
        if self.soundOn {
            self.soundButton.tintColor = nil
            self.soundButton.setImage(UIImage(systemName: "speaker.wave.2.fill"), for: .normal)
        } else {
            self.soundButton.tintColor = .systemGray
            self.soundButton.setImage(UIImage(systemName: "speaker.slash.fill"), for: .normal)
        }
    }
}

extension PlayerViewController {
    private func smoothSeekInner(completionHandler: @escaping (Bool) -> Void) {
        self.seekInProgress = true
        let to = self.seekChaseTime

        if player.currentItem != nil {
            player.seek(to: to, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero) { [weak self] success in
                guard let `self` = self else {
                    self?.seekInProgress = false
                    return
                }
                if CMTimeCompare(to, self.seekChaseTime) == 0 {
                    self.seekInProgress = false
                    completionHandler(success)
                } else {
                    self.smoothSeekInner(completionHandler: completionHandler)
                }
            }
        } else if let pointCloudPlayer = pointCloudPlayer {
            _ = pointCloudPlayer.seek(time: to)
            if CMTimeCompare(to, self.seekChaseTime) == 0 {
                self.seekInProgress = false
                completionHandler(true)
            } else {
                self.smoothSeekInner(completionHandler: completionHandler)
            }
        }
    }

    func smoothSeek(to: CMTime, completionHandler: @escaping (Bool) -> Void) {
        guard player.currentItem?.status == .readyToPlay || pointCloudPlayer != nil else {
            self.seekInProgress = false
            return
        }
        if CMTimeCompare(to, seekChaseTime) == 0 {
            return
        }
        self.seekChaseTime = to
        if self.seekInProgress {
            return
        }
        smoothSeekInner(completionHandler: completionHandler)
    }

    @objc func rangeSliderValueChanged(_ rangeSlider: RangeSlider) {
        var t: CMTime!
        switch rangeSlider.active {
        case .thumb:
            t = CMTime(seconds: Double(rangeSlider.thumb), preferredTimescale: 600)
            self.smoothSeek(to: t, completionHandler: { _ in })
        case .lowerBound:
            t = CMTime(seconds: Double(rangeSlider.lowerBound), preferredTimescale: 600)
            self.smoothSeek(to: t) { success in
                if let currentItem = self.player.currentItem {
                    rangeSlider.lowerBound = CGFloat(currentItem.currentTime().seconds)
                }
            }
        case .upperBound:
            t = CMTime(seconds: Double(rangeSlider.upperBound), preferredTimescale: 600)
            self.smoothSeek(to: t) { success in
                if let currentItem = self.player.currentItem {
                    rangeSlider.upperBound = CGFloat(currentItem.currentTime().seconds)
                }
            }
        }
        setupPlayRange(Double(rangeSlider.lowerBound), Double(rangeSlider.upperBound))
    }
    
    func setupPlayRange(_ min: Double, _ max: Double) {
        if player.currentItem != nil {
            // self.player?.currentItem?.forwardPlaybackEndTime = endTime
            if let boundaryTimeObserverToken = boundaryTimeObserverToken {
                player.removeTimeObserver(boundaryTimeObserverToken)
                self.boundaryTimeObserverToken = nil
            }
            var times = [NSValue]()
            times.append(NSValue(time: CMTime(seconds: max, preferredTimescale: 600)))
            boundaryTimeObserverToken = player.addBoundaryTimeObserver(forTimes: times, queue: .main) { [weak self] in
                if let currentItem = self!.player.currentItem {
                    if !self!.isRepeat {
                        self!.player.pause()
                    } else {
                        let startTime = CMTime(seconds: min, preferredTimescale: 600)
                        currentItem.seek(to: startTime, completionHandler: nil)
                        self!.player.playImmediately(atRate: self!.playSpeed)
                    }
                }
            }
        }
    }
}

extension PlayerViewController {
    func doPose(pixels: CVPixelBuffer, time: CMTime, freeze: Bool = false) {
        if let golfer = poseCollection.seek(to: time.seconds), time.equalInMsec(seconds: golfer.time) {
            log("using loaded one")
            let valid = poser1.isValidPose(golfer)
            if !freeze {
                overlayView.setPose(valid ? golfer : nil, time)
            } else {
                if valid {
                    overlayView.pushPose(pose: golfer, snap: nil, time: time)
                }
            }
            // self.log("%%%: " + String(format: "%.1f leftAnkle=%.1f rightAnkle=%.1f leftKnee=%.1f rightKnee=%.1f leftHip=%.1f rightHip=%.1f", golfer.score, golfer.leftAnkle.score, golfer.rightAnkle.score, golfer.leftKnee.score, golfer.rightKnee.score, golfer.leftHip.score, golfer.rightHip.score))
            self.log("%%%: " + String(format: "%.1f v=(%.1f, %.1f)", golfer.score, golfer.wrist.vx / 1000, golfer.wrist.vy / 1000))
            DispatchQueue.main.async {
                self.overlayView.draw(size: pixels.size)
            }
        } else {
            poser1.runModel(assetId: assetId, targetView: overlayView, pixelBuffer: pixels, transform: reverseTransform!, time: time, freeze: false) { _ in }
        }
    }

    @objc func displayLinkFired(link: CADisplayLink) {
        let currentTime = playerItemVideoOutput.itemTime(forHostTime: CACurrentMediaTime())
        if playerItemVideoOutput.hasNewPixelBuffer(forItemTime: currentTime) {
            if let buffer = playerItemVideoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) {
                // let frameImage = CIImage(cvImageBuffer: buffer)

                if self.showPose {
                    switch self.poseEngine {
                    case .posenet:
                        poser2.runModel(targetView: overlayView, pixelBuffer: buffer)
                    case .movenetLightning, .movenetThunder:
                        // poser1.runModel(assetId: self.assetId, targetView: overlayView, pixelBuffer: buffer, transform: self.reverseTransform!, time: currentTime, freeze: false) { _ in }
                        doPose(pixels: buffer, time: currentTime, freeze: false)
                    default:
                        break
                    }
                }
                if self.showSegments {
                    deepLab.runModel(assetId: self.assetId!, targetView: overlayView, image: buffer, transform: self.reverseTransform!, time: currentTime)
                }
            }
        }
    }
}

extension PlayerViewController {
    func getFrameImage(asset: AVAsset, time: CMTime) -> CGImage? {
        let imgGen = AVAssetImageGenerator(asset: asset)
        imgGen.requestedTimeToleranceBefore = CMTime.zero
        imgGen.requestedTimeToleranceAfter = CMTime.zero
        return try? imgGen.copyCGImage(at: time, actualTime: nil)
    }

    func getFramePixelBuffer(asset: AVAsset, time: CMTime) -> CVPixelBuffer? {
        return getFrameImage(asset: asset, time: time)?.pixelBuffer()
    }

    func refreshOverlayWithCurrentFrame() {
        guard let item = self.player.currentItem else { return }
        let currentTime = item.currentTime()
        guard let pixelBuffer = self.getFramePixelBuffer(asset: item.asset, time: currentTime) else { return }
        if self.showPose {
            self.poser1.runModel(assetId: self.assetId!, targetView: self.overlayView, pixelBuffer: pixelBuffer, transform: self.reverseTransform!, time: currentTime, freeze: false) { _ in
            }
        } else {
            self.overlayView.setPose(nil, CMTime.zero)
        }
        if self.showSegments {
            deepLab.runModel(assetId: self.assetId!, targetView: overlayView, image: pixelBuffer, transform: self.reverseTransform!, time: currentTime)
        } else {
            self.overlayView.setSnap(nil, CMTime.zero)
        }
        self.overlayView.draw(size: CGSize(width: pixelBuffer.size.height, height: pixelBuffer.size.width))
    }
}

extension PlayerViewController {
    func initSceneView() {
        let scene = SCNScene()

        // create and add a camera to the scene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        scene.rootNode.addChildNode(cameraNode)

        // place the camera
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 0)
        cameraNode.camera!.zNear = 0
        cameraNode.camera!.automaticallyAdjustsZRange = true

        /*
        // create and add a light to the scene
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        scene.rootNode.addChildNode(lightNode)

        // create and add an ambient light to the scene
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.color = UIColor.white
        scene.rootNode.addChildNode(ambientLightNode)
        */

        let axes = PointCloud.buildAxes()
        scene.rootNode.addChildNode(axes)

        sceneView.scene = scene
        sceneView.allowsCameraControl = true
    }
}

extension PlayerViewController {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self.playerView
    }
}

extension PlayerViewController {
    func log(_ msg: String) {
        let max = 20000
        DispatchQueue.main.async {
            if let logView = self.textLogView {
                logView.text += msg + "\n"
                let len = logView.text.count
                if len > max  {
                    let startIndex = logView.text.index(logView.text.startIndex, offsetBy: len-max)
                    logView.text = String(logView.text[startIndex...])
                }
                logView.scrollRangeToVisible(NSMakeRange(logView.text.count - 1, 0))
            }
        }
        print(msg)
    }
}
