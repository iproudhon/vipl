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

    @IBOutlet var playerView: PlayerView!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var frameBackButton: UIButton!
    @IBOutlet weak var frameForwardButton: UIButton!
    @IBOutlet weak var playPauseButton: UIButton!
    @IBOutlet weak var repeatButton: UIButton!
    @IBOutlet weak var playSpeedMenu: UIButton!
    @IBOutlet weak var rangeButton: UIButton!
    @IBOutlet weak var saveButton: UIButton!
    @IBOutlet weak var dismissButton: UIButton!
    @IBOutlet weak var overlayView: OverlayView!
    
    private let rangeSlider = RangeSlider(frame: .zero)

    // for seek
    private var seekInProgress = false
    private var seekChaseTime = CMTime.zero
    
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
        var lower = Swift.max(self.rangeSlider.min, self.rangeSlider.thumb - CGFloat(1.5))
        var upper = Swift.min(self.rangeSlider.thumb + CGFloat(1.5), self.rangeSlider.max)
        
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
                        do {
                            try FileManager.default.removeItem(at: orgUrl)
                            try FileManager.default.moveItem(at: url, to: orgUrl)
                        } catch {
                            print("Failed to remove existing file: \(error.localizedDescription)")
                            return
                        }
                        self.player.replaceCurrentItem(with: AVPlayerItem(url: orgUrl))
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
        self.player.playImmediately(atRate: playSpeed)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // initialize the range slider
        view.addSubview(rangeSlider)
        rangeSlider.addTarget(self, action: #selector(rangeSliderValueChanged(_:)),
                              for: .valueChanged)

        poser1.updateModel()
        do {
            poser2 = try PoseNet()
        } catch {
            fatalError("Failed to load posenet model. \(error.localizedDescription)")
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        guard let url = url else { return }
        setupPlaySpeedMenu()
        setupSaveMenu()
        setupRangeMenu()

        playerView.player = player
        setupPlayerObservers()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
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
        let margin: CGFloat = 40
        let width = view.bounds.width - 2 * margin
        let height: CGFloat = 30

        let x = (view.bounds.width - width) / 2
        let y = (view.bounds.height - height * 3.7)
        rangeSlider.frame = CGRect(x: x, y: y, width: width, height: height)
    }

    func playUrl(url: URL) {
        self.url = url
        setupPlaySpeedMenu()
        setupSaveMenu()
        setupRangeMenu()

        playerView.player = player
        setupPlayerObservers()
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
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
    
    func setupSaveMenu() {
        var options = [UIAction]()
        var item = UIAction(title: "Save", state: .off, handler: {_ in
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
        let menu = UIMenu(title: "Save", children: options)
        
        saveButton.showsMenuAsPrimaryAction = true
        saveButton.menu = menu
    }

    func setupRangeMenu() {
        func do_it(_ lowerOffset: Double, _ upperOffset: Double) {
            let lower = Swift.max(self.rangeSlider.min, self.rangeSlider.thumb - CGFloat(lowerOffset))
            let upper = Swift.min(self.rangeSlider.thumb + CGFloat(upperOffset), self.rangeSlider.max)
            self.rangeSlider.lowerBound = lower
            self.rangeSlider.upperBound = upper
            self.setupPlayRange(lower, upper)
        }

        var options = [UIAction]()
        var item = UIAction(title: "Reset", state: .off, handler: { _ in
            self.rangeSlider.lowerBound = self.rangeSlider.min
            self.rangeSlider.upperBound = self.rangeSlider.max
            self.setupPlayRange(self.rangeSlider.min, self.rangeSlider.max)
        })
        options.insert(item, at: 0)
        item = UIAction(title: "1.5 : 1.5", state: .off, handler: { _ in
            do_it(1.5, 1.5)
        })
        options.insert(item, at: 0)
        item = UIAction(title: "2.0 : 5.0", state: .off, handler: { _ in
            do_it(2.0, 5.0)
        })
        options.insert(item, at: 0)
        item = UIAction(title: "0.3 : 0.2", state: .off, handler: { _ in
            do_it(0.3, 0.2)
        })
        options.insert(item, at: 0)

        let menu = UIMenu(title: "Ranges", children: options)
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
        let img = self.isRepeat ? UIImage(systemName: "repeat.circle.fill") : UIImage(systemName: "repeat.circle")
        guard let img = img else { return }
        self.repeatButton.setImage(img, for: .normal)
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
                let which = "movenet"
                switch which {
                case "movenet":
                    let transform = CGAffineTransform(rotationAngle: .pi*3.0/2.0)
                    poser1.runModel(targetView: overlayView, pixelBuffer: buffer, transform: transform)
                case "posenet":
                    poser2.runModel(targetView: overlayView, pixelBuffer: buffer)
                default:
                    let transform = CGAffineTransform(rotationAngle: .pi/2)
                    poser1.runModel(targetView: overlayView, pixelBuffer: buffer, transform: transform)
                }
            }
        }
    }
}
