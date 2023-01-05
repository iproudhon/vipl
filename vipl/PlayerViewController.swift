//
//  PlayerViewController.swift
//  vipl
//
//  Created by Steve H. Jung on 12/12/22.
//

import Foundation
import AVFoundation
import AVKit
import UIKit
import MobileCoreServices

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

class PlayerViewController: UIViewController, UIImagePickerControllerDelegate, UIDocumentPickerDelegate, UINavigationControllerDelegate {
    
    let player = AVPlayer()
    let playerItemVideoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA])
    lazy var displayLink: CADisplayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired(link:)))
    var assetId: String?

    // video asset orientation & camera position
    private var orientation: UIDeviceOrientation?
    private var position: AVCaptureDevice.Position?
    private var transform: CGAffineTransform?
    private var reverseTransform: CGAffineTransform?

    @IBOutlet var playerView: PlayerView!
    @IBOutlet weak var timeLabel: UILabel!
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
    
    private let rangeSlider = RangeSlider(frame: .zero)

    // for seek
    private var seekInProgress = false
    private var seekChaseTime = CMTime.zero

    private enum PoseEngine {
        case none, posenet, posenetTf, movenetLightning, movenetThunder
    }
    private var poseEngine: PoseEngine = .movenetLightning
    private var showPose = false

    private var showSegments = false
    
    @IBAction func dismiss(_ sender: Any) {
        self.dismiss(animated: true)
    }
    
    @IBAction func play_pause(_ sender: Any) {
    }
    
    @IBAction func stepBack(_ sender: Any) {
        guard let currentItem = player.currentItem else { return }
        if currentItem.canStepBackward {
            currentItem.step(byCount: -1)
        }
    }
    
    @IBAction func stepForward(_ sender: Any) {
        guard let currentItem = player.currentItem else { return }
        if currentItem.canStepForward {
            currentItem.step(byCount: 1)
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
    
    private func getNextFileName() -> String {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        var num = UserDefaults.standard.integer(forKey: "swing-number")
        if num == 0 {
            num = 1
        }
        while true {
            let fileName = dir[0].appendingPathComponent("swing-\(String(format: "%04d", num))").appendingPathExtension("mov")
            if FileManager.default.fileExists(atPath: fileName.path) {
                num += 1
                continue
            }
            UserDefaults.standard.set(num + 1, forKey: "swing-number")
            return fileName.path
        }
    }

    private func setAssetId(asset: AVAsset?) {
        guard let asset = asset as? AVURLAsset,
        let creationDate = asset.creationDate?.value as? Date else {
            self.assetId = ""
            return
        }
        let v = Int64(creationDate.timeIntervalSince1970 * 1000) * Int64(asset.duration.seconds * 1000)
        self.assetId = "\(asset.url.lastPathComponent):\(v)"
    }

    @IBAction func save(asNew: Bool) {
        guard let currentItem = self.player.currentItem else { return }

        let url: URL!
        if !asNew {
            let fn = NSUUID().uuidString
            let path = (NSTemporaryDirectory() as NSString).appendingPathComponent((fn as NSString).appendingPathExtension("mov")!)
            url = URL(fileURLWithPath: path)
        } else {
            url = URL(fileURLWithPath: getNextFileName())
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
                        self.setAssetId(asset: nil)
                        do {
                            try FileManager.default.removeItem(at: orgUrl)
                            try FileManager.default.moveItem(at: url, to: orgUrl)
                        } catch {
                            print("Failed to remove existing file: \(error.localizedDescription)")
                            return
                        }
                        self.player.replaceCurrentItem(with: AVPlayerItem(url: orgUrl))
                        self.setAssetId(asset: self.player.currentItem?.asset)
                        print("Video saved to \(String(describing: orgUrl.path))")
                    }
                }
            }
        })
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
        let url = urls[0]
        self.playerView.player = player
        self.setupPlayerObservers()
        self.player.replaceCurrentItem(with: AVPlayerItem(url: url))
        self.setAssetId(asset: self.player.currentItem?.asset)
        self.player.playImmediately(atRate: playSpeed)
    }
    
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true, completion: nil)
        guard let url = info[.mediaURL] as? URL else { return }
        self.playerView.player = player
        self.setupPlayerObservers()
        self.player.replaceCurrentItem(with: AVPlayerItem(url: url))
        self.setAssetId(asset: self.player.currentItem?.asset)
        self.player.playImmediately(atRate: playSpeed)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // initialize the range slider
        view.addSubview(rangeSlider)
        rangeSlider.addTarget(self, action: #selector(rangeSliderValueChanged(_:)),
                              for: .valueChanged)

        self.poseButton.tintColor = .systemGray

        DispatchQueue.main.async {
            self.poser1.updateModel()
            do {
                self.poser2 = try PoseNet()
                self.deepLab = DeepLab()
            } catch {
                fatalError("Failed to load posenet model. \(error.localizedDescription)")
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        guard let url = url else { return }
        setupPlaySpeedMenu()
        setupMainMenu()
        setupRangeMenu()

        playerView.player = player
        setupPlayerObservers()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        self.setAssetId(asset: self.player.currentItem?.asset)
        if let asset = self.player.currentItem?.asset {
            (self.orientation, self.position, self.transform, self.reverseTransform) = asset.videoOrientation()
        }
        player.playImmediately(atRate: playSpeed)
    }

    override func viewWillDisappear(_ animated: Bool) {
        player.pause()
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
        let buttonWidth = 20, buttonHeight = 20, sliderHeight = 30, sliderMargin = 30, timeLabelWidth = 100
        var x, y: CGFloat

        // player view
        self.playerView.frame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - CGFloat(Int(buttonHeight * 3 / 2)) - CGFloat(sliderHeight))
        self.overlayView.frame.size = self.playerView.frame.size
        self.dismissButton.frame.origin = CGPoint(x: self.playerView.frame.size.width - self.dismissButton.frame.size.width, y: 0)

        // range slider
        x = rect.minX + CGFloat(sliderMargin)
        y = self.playerView.frame.origin.y + self.playerView.frame.size.height + 1
        self.rangeSlider.frame = CGRect(x: x, y: y, width: rect.width - CGFloat(2 * sliderMargin), height: CGFloat(sliderHeight))

        y = rangeSlider.frame.origin.y + rangeSlider.frame.size.height * 4 / 3
        x = rect.minX + CGFloat(buttonWidth)
        self.poseButton.frame = CGRect(x: x, y: y, width: CGFloat(buttonWidth), height: CGFloat(buttonHeight))
        x += self.poseButton.frame.size.width

        self.repeatButton.frame = CGRect(x: x, y: y, width: CGFloat(buttonWidth), height: CGFloat(buttonHeight))
        x += self.repeatButton.frame.size.width

        self.playSpeedMenu.frame = CGRect(x: x, y: y, width: self.playSpeedMenu.frame.size.width, height: CGFloat(buttonHeight))
        x += self.playSpeedMenu.frame.size.width

        self.rangeButton.frame = CGRect(x: x, y: y, width: CGFloat(buttonWidth), height: CGFloat(buttonHeight))
        x += self.rangeButton.frame.size.width

        // center buttons
        x = rect.minX + (rect.width - CGFloat(buttonWidth) * 6) / 2
        self.frameBackButton.frame = CGRect(x: x, y: y, width: CGFloat(buttonWidth * 2), height: CGFloat(buttonHeight))
        x += self.frameBackButton.frame.size.width

        self.playPauseButton.frame = CGRect(x: x, y: y, width: CGFloat(buttonWidth * 2), height: CGFloat(buttonHeight))
        x += self.playPauseButton.frame.size.width

        self.frameForwardButton.frame = CGRect(x: x, y: y, width: CGFloat(buttonWidth * 2), height: CGFloat(buttonHeight))
        x += self.frameForwardButton.frame.size.width

        // right side buttons
        x = rect.minX + rect.width - CGFloat(buttonWidth * 2 + timeLabelWidth)
        self.timeLabel.frame = CGRect(x: x, y: y, width: CGFloat(timeLabelWidth), height: CGFloat(buttonHeight))
        x += CGFloat(timeLabelWidth)

        self.menuButton.frame = CGRect(x: x, y: y, width: CGFloat(buttonWidth), height: CGFloat(buttonHeight))
    }

    func playUrl(url: URL) {
        self.url = url
        setupPlaySpeedMenu()
        setupMainMenu()
        setupRangeMenu()

        playerView.player = player
        setupPlayerObservers()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        self.setAssetId(asset: self.player.currentItem?.asset)
        player.playImmediately(atRate: playSpeed)
    }
    
    func setupPlaySpeedMenu() {
        let doit = {(action: UIAction) in
            guard let rate = Float(action.title) else { return }
            self.playSpeed = rate
            self.player.rate = rate
        }
        var options = [UIAction]()
        for i in ["0.05", "0.1", "0.2", "0.5", "1", "1.25", "1.5", "2"] {
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
        var item = UIAction(title: "Toggle Segments", state: .off, handler: {_ in
            self.showSegments = !self.showSegments
            self.refreshOverlayWithCurrentFrame()
        })
        options.insert(item, at: 0)
        item = UIAction(title: "Save", state: .off, handler: {_ in
            self.save(asNew: false)
        })
        options.insert(item, at: 0)
        item = UIAction(title: "Save as New", state: .off, handler: {_ in
            self.save(asNew: true)
        })
        options.insert(item, at: 0)
        item = UIAction(title: "Delete", state: .off, handler: {_ in
            if let url = self.url {
                try? FileManager.default.removeItem(at: url)
            }
            self.dismiss(animated: true)
        })
        options.insert(item, at: 0)
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
        var item = UIAction(title: "Reset Range", state: .off, handler: { _ in
            self.rangeSlider.lowerBound = self.rangeSlider.min
            self.rangeSlider.upperBound = self.rangeSlider.max
            self.setupPlayRange(self.rangeSlider.min, self.rangeSlider.max)
        })
        options.insert(item, at: 0)
        item = UIAction(title: "1.5 : 1.5", state: .off, handler: { _ in
            do_range(1.5, 1.5)
        })
        options.insert(item, at: 0)
        item = UIAction(title: "2.0 : 5.0", state: .off, handler: { _ in
            do_range(2.0, 5.0)
        })
        options.insert(item, at: 0)
        item = UIAction(title: "0.3 : 0.2", state: .off, handler: { _ in
            do_range(0.3, 0.2)
        })
        options.insert(item, at: 0)

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
                    poser1.runModel(assetId: self.assetId!, targetView: self.overlayView, pixelBuffer: pixelBuffer, transform: self.reverseTransform!, time: currentTime, freeze: true)
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
        item = UIAction(title: "Reset Overlay", state: .off, handler: { _ in
            do_poses("reset")
        })
        options.insert(item, at: 0)
        item = UIAction(title: "Freeze", state: .off, handler: { _ in
            do_poses("freeze-both")
        })
        options.insert(item, at: 0)
        item = UIAction(title: "Freeze Pose", state: .off, handler: { _ in
            do_poses("freeze-pose")
        })
        options.insert(item, at: 0)
        item = UIAction(title: "Freeze Body", state: .off, handler: { _ in
            do_poses("freeze-body")
        })
        options.insert(item, at: 0)

        let menu = UIMenu(title: "Ranges & Overlays", children: options)
        rangeButton.showsMenuAsPrimaryAction = true
        rangeButton.menu = menu
    }

    func setupPlayerObservers() {
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
                }
            }
            DispatchQueue.main.async {
                self.updateUIForPlayerItemStatus()
            }
        }
    }
    
    @IBAction func togglePlay(_ sender: Any) {
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
        guard let currentItem = player.currentItem else { return }
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
    }

    @IBAction func toggleShowPose(_ sender: Any) {
        self.showPose = !self.showPose
        self.poseButton.tintColor = self.showPose ? nil : .systemGray
        self.refreshOverlayWithCurrentFrame()
    }
}

extension PlayerViewController {
    private func smoothSeekInner(completionHandler: @escaping (Bool) -> Void) {
        self.seekInProgress = true
        let to = self.seekChaseTime
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
    }

    private func smoothSeek(to: CMTime, completionHandler: @escaping (Bool) -> Void) {
        guard player.currentItem?.status == .readyToPlay else {
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

extension PlayerViewController {
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
                        poser1.runModel(assetId: self.assetId!, targetView: overlayView, pixelBuffer: buffer, transform: self.reverseTransform!, time: currentTime)
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
            self.poser1.runModel(assetId: self.assetId!, targetView: self.overlayView, pixelBuffer: pixelBuffer, transform: self.reverseTransform!, time: currentTime)
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
