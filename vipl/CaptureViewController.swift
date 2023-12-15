//
//  CaptureViewController.swift
//  vipl
//
//  Created by Steve H. Jung on 12/14/22.
//

import AVFoundation
import CoreMotion
import CoreLocation
import Photos
import AVKit
import UIKit
import SceneKit
import MobileCoreServices
import Vision

class CaptureViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate, AVCaptureMetadataOutputObjectsDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureDataOutputSynchronizerDelegate {

    // if set, ignores orientation and treat it as .landscapeRight to avoid unnecessary transforms
    public var ignoreOrientation: Bool = true

    private var spinner: UIActivityIndicatorView!

    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }

    let locationManager = CLLocationManager()
    let motionManager = CMMotionManager()

    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

    private let session = AVCaptureSession()
    private var isSessionRunning = false
    private var selectedSemanticSegmentationMatteTypes = [AVSemanticSegmentationMatte.MatteType]()

    private let sessionQueue = DispatchQueue(label: "session.queue")
    private var setupResult: SessionSetupResult = .success

    private var chosenCamera: CaptureCameraType?
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!

    private var outputSync: AVCaptureDataOutputSynchronizer!
    private var videoOutput: AVCaptureVideoDataOutput!
    private var depthDataOutput: AVCaptureDepthDataOutput!
    private var metadataOutput: AVCaptureMetadataOutput!
    private var audioOutput: AVCaptureAudioDataOutput!
    private var assetWriter: AVAssetWriter!

    private var transform: CGAffineTransform! = CGAffineTransformIdentity
    private var reverseTransform: CGAffineTransform! = CGAffineTransformIdentity
    private var isMirrored: Bool = false

    @IBOutlet private weak var containerView: UIView!
    @IBOutlet private weak var previewView: CapturePreviewView!
    @IBOutlet private weak var camerasMenu: UIButton!
    @IBOutlet private weak var menuButton: UIButton!

    @IBOutlet private weak var capturedVideoView: UIView!
    @IBOutlet private weak var capturedVideoViewImg: UIImageView!
    @IBOutlet private weak var dismissCapturedVideoButton: UIButton!

    @IBOutlet private weak var overlayView: OverlayView!
    @IBOutlet private weak var gravityView: GravityView!
    @IBOutlet private weak var sceneView: SCNView!
    @IBOutlet private weak var textLogView: UITextView!

    let rangeSlider = RangeSlider(frame: .zero)
    
    private var capturedMovieUrl: URL?
    private var tmpMovieUrl: URL?

    private var showPose: Bool = false
    private var poser = Poser()
    private var poserTime: Date?
    private var poserTimeThreshold: TimeInterval = 0.05

    private var useGestureSwitch = true
    private var useGestureTime: Date?
    private var useGestureTimeThreshold: TimeInterval = 2

    // focus point
    private var focusPoint = CGPoint(x: 0, y: 0)

    // point cloud stuff
    private var depthDataFilter: Bool = false
    private var pointClouds: PointCloudCollection?
    private var sceneViewMode: Int = 0
    private var cmdCapturePointCloud: Int = 0
    private let ptcldSem = DispatchSemaphore(value: 1)
    private var showHeatmap: Bool = false
    private var freezePointCloud: Bool = false


    // gravity view stuff
    enum GravityMode {
        case none       // no action
        case grid       // show tilted axis & grid
        case axis       // show tilted image with fixed axis & grid
        case tilt       // show tilted image, no axis or grid
    }
    private var gravityMode: GravityMode = .grid
    private var gravity: CMAcceleration?


    override func viewDidLoad() {
        super.viewDidLoad()

        switch UserDefaults.standard.string(forKey: "capture-gravity-mode") ?? "grid" {
        case "grid":
            self.gravityMode = .grid
        case "axis":
            self.gravityMode = .axis
        case "tilt":
            self.gravityMode = .tilt
        case "none":
            fallthrough
        default:
            self.gravityMode = .none
        }

        view.addSubview(rangeSlider)
        rangeSlider.addTarget(self, action: #selector(rangeSliderValueChanged(_:)), for: .valueChanged)

        setupLayout()
        initGravityView()

        self.pointClouds = PointCloudCollection(scnView: sceneView, count: 100)
        self.overlayView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focusAndExposeTap(_:))))

        setupMainMenu()
        if self.chosenCamera == nil {
            if let name = UserDefaults.standard.string(forKey: "the-camera") {
                let cameras = CaptureHelper.listCameras()
                self.chosenCamera = cameras?[name] ?? nil
            }
        }
        setupCameraSelectionMenu()
        
        // TODO: setup the video preview view
        previewView.session = session
        
        capturedMovieUrl = nil
        tmpMovieUrl = FileSystemHelper.getPrimaryTemporaryFileName()

        // register tap for captured video viewer
        capturedVideoView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.tapCapturedVideoView(_:))))

        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
        default:
            setupResult = .notAuthorized
        }
        
        sessionQueue.async {
            self.configureSession()
        }
        DispatchQueue.main.async {
            self.spinner = UIActivityIndicatorView(style: .large)
            self.spinner.color = UIColor.yellow
            self.previewView.addSubview(self.spinner)
            self.initSceneView()
        }
        DispatchQueue.main.async {
            self.poser.updateModel(modelType: .movenetLighting)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                self.addObservers()
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
            case .notAuthorized:
                DispatchQueue.main.async {
                    let changePrivacySetting = "<XXX> doesn't have permission to use the camera, please change privacy settings"
                    let message = NSLocalizedString(changePrivacySetting, comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "<XXX>", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
            case .configurationFailed:
                DispatchQueue.main.async {
                    let alertMsg = "Alert message when something goes wrong during capture session configuration"
                    let message = NSLocalizedString("Unable to capture media", comment: alertMsg)
                    let alertController = UIAlertController(title: "<XXX>", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    self.present(alertController, animated: true, completion: nil)
                }
            }
        }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        refreshCapturedVideoView()
    }

    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if let movieOut = self.movieOut, movieOut.isRecording {
                movieOut.stop(completionHandler: self.onStopRecording)
            }
            if let pointCloudOut = self.pointCloudOut {
                pointCloudOut.close()
                self.pointCloudOut = nil
                self.onStopRecording()
            }
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        super.viewWillDisappear(animated)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        setupLayout()
        self.refreshCapturedVideoView()
    }

    private func setupLayout() {
        switch windowOrientation {
        case .unknown:
            break
        case .portrait:
            locationManager.headingOrientation = .portrait
        case .portraitUpsideDown:
            locationManager.headingOrientation = .portraitUpsideDown
        case .landscapeLeft:
            locationManager.headingOrientation = .landscapeLeft
        case .landscapeRight:
            locationManager.headingOrientation = .landscapeRight
        @unknown default:
            break
        }

        // previewView
        //   overlayView, gravityView
        //   xButton, camerasMenu, menuButton
        //   durationLabel
        //   sceneView
        // textLogView
        // captureButton
        let rect = CGRect(x: view.safeAreaInsets.left,
                          y: view.safeAreaInsets.top,
                          width: view.bounds.width - (view.safeAreaInsets.left + view.safeAreaInsets.right),
                          height: view.bounds.height - (view.safeAreaInsets.top + view.safeAreaInsets.bottom))
        let buttonSize = 60, buttonMargin = 5
        var x, y, height: CGFloat

        height = rect.height - CGFloat(buttonSize + 2 * buttonMargin)
        if view.bounds.width < view.bounds.height {
            // vertical
            self.containerView.frame = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height)
            self.previewView.frame = CGRect(x: 0, y: 0, width: rect.width, height: height)
        } else {
            // horizontal
            self.containerView.frame = CGRect(x: rect.minX, y: 0, width: rect.width, height: view.bounds.height)
            self.previewView.frame = CGRect(x: 0, y: 0, width: rect.width, height: view.bounds.height)
        }
        self.previewView.layer.zPosition = -100000
        self.overlayView.frame = CGRect(x: 0, y: 0, width: self.previewView.frame.width, height: self.previewView.frame.height)
        self.gravityView.frame = CGRect(x: 0, y: 0, width: self.previewView.frame.width, height: self.previewView.frame.height)
        self.xButton.frame.origin = CGPoint(x: 0, y: 0)
        x = CGFloat(buttonMargin) * 2 + self.xButton.frame.width
        self.camerasMenu.frame.origin = CGPoint(x: x, y: CGFloat(buttonMargin))
        self.menuButton.frame.origin = CGPoint(x: self.containerView.frame.width - self.menuButton.frame.size.width, y: 0)
        self.durationLabel.frame.origin = CGPoint(x: (self.containerView.frame.width - self.durationLabel.frame.width) / 2, y: self.camerasMenu.frame.origin.y + self.camerasMenu.frame.height + 10)

        y = self.containerView.frame.origin.y + self.containerView.frame.height
        height = rect.minY + rect.height - y
        self.textLogView.frame = CGRect(x: rect.minX, y: self.containerView.frame.origin.y + self.containerView.frame.size.height, width: rect.width, height: height)

        x = rect.minX + (rect.width - CGFloat(buttonSize)) / 2
        if view.bounds.width < view.bounds.height {
            // vertical
            y = self.containerView.frame.origin.y + self.containerView.frame.size.height
            y += ((rect.minY + rect.height - y) - CGFloat(buttonSize)) / 2
        } else {
            // horizontal
            y = view.bounds.height - CGFloat(buttonSize) * 3 / 2
        }
        self.recordButton.frame = CGRect(x: x, y: y, width: CGFloat(buttonSize), height: CGFloat(buttonSize))

        self.previewView.layer.transform = CATransform3DIdentity
        self.gravityView.layer.transform = CATransform3DIdentity

        self.refreshSceneView()
    }

    override var shouldAutorotate: Bool {
        return !(movieOut?.isRecording ?? false || pointCloudOut != nil)
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        setupLayout()

        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation), deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                return
            }
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
            if let videoSettings = self.videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov) {
                (self.transform, self.reverseTransform) = self.getCaptureTransform(orientation: newVideoOrientation, isMirrored: videoPreviewLayerConnection.isVideoMirrored, videoSettings: videoSettings)
                self.isMirrored = videoPreviewLayerConnection.isVideoMirrored
            }
            if let connection = self.videoOutput.connection(with: .video) {
                connection.videoOrientation = newVideoOrientation
            }
            if let connection = self.depthDataOutput.connection(with: .depthData) {
                connection.videoOrientation = newVideoOrientation
                connection.isVideoMirrored = videoPreviewLayerConnection.isVideoMirrored
            }
        }

        coordinator.animate(alongsideTransition: nil) { _ in
            self.refreshCapturedVideoView()
        }
    }

    private func configureSession() {
        if setupResult != .success {
            return
        }

        session.beginConfiguration()
        // audio input device
        do {
            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)

            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
            } else {
                print("Can't add audio device input to the session")
            }
        } catch {
            print("Can't create audio device input: \(error)")
        }
        session.commitConfiguration()

        // video input device
        setupResult = self.selectCamera()

        DispatchQueue.main.async {
            if self.windowOrientation != .unknown,
               let orientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                self.previewView.videoPreviewLayer.connection?.videoOrientation = orientation
            }
        }
    }
    
    @IBAction private func resumeInterruptedSession(_ resumeButton: UIButton) {
        sessionQueue.async {
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "<XXX>", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.resumeButton.isHidden = true
                }
            }
        }
    }
    
    @IBOutlet weak var xButton: UIButton!
    
    @IBAction func dismiss(_ sender: Any) {
        self.dismiss(animated: true)
    }

    // should run inside session.queue
    private func setupOutput(depthEnabled: Bool) {
        // remove outputs first
        for i in self.session.outputs {
            self.session.removeOutput(i)
        }
        self.videoOutput = nil
        self.depthDataOutput = nil
        self.audioOutput = nil
        self.metadataOutput = nil

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = false
        // videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as String) : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey) : kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)

        let depthDataOutput = AVCaptureDepthDataOutput()
        depthDataOutput.isFilteringEnabled = self.depthDataFilter
        depthDataOutput.alwaysDiscardsLateDepthData = false
        depthDataOutput.setDelegate(self, callbackQueue: self.sessionQueue)

        // TODO: unused yet
        let metadataOutput = AVCaptureMetadataOutput()
        metadataOutput.setMetadataObjectsDelegate(self, queue: self.sessionQueue)

        let audioOutput = AVCaptureAudioDataOutput()
        audioOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)

        if self.session.canAddOutput(videoOutput) &&
            self.session.canAddOutput(audioOutput) {
            self.session.addOutput(videoOutput)
            self.session.addOutput(audioOutput)
        } else {
            self.session.commitConfiguration()
            fatalError("Can't add video or audio output to the capture session")
        }
        if depthEnabled && self.session.canAddOutput(depthDataOutput) {
            self.session.addOutput(depthDataOutput)
        }
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
        // if self.session.canAddOutput(metadataOutput) {
        //     self.session.addOutput(metadataOutput)
        // }

        self.videoOutput = videoOutput
        self.depthDataOutput = depthDataOutput
        self.metadataOutput = metadataOutput
        self.audioOutput = audioOutput
    }

    private func setupSyncedOutputs(depthEnabled: Bool) {
        var outputs = [AVCaptureOutput]()
        if let videoOutput = self.videoOutput,
           let audioOutput = self.audioOutput {
            outputs.append(videoOutput)
            outputs.append(audioOutput)
        }
        if depthEnabled,
           let depthDataOutput = self.depthDataOutput,
           depthDataOutput.connection(with: .depthData) != nil {
            outputs.append(depthDataOutput)
        }
        let outputSync = AVCaptureDataOutputSynchronizer(dataOutputs: outputs)
        outputSync.setDelegate(self, queue: self.sessionQueue)
        self.outputSync = outputSync
    }
    
    @IBOutlet private weak var cameraButton: UIButton!
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!
    @IBOutlet private weak var durationLabel: UILabel!
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera, .builtInDualWideCamera], mediaType: .video, position: .unspecified)
    
//    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
    @objc func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
        print("XXX: \(gestureRecognizer.location(in: gestureRecognizer.view)) -> \(devicePoint)")
        focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            let device = self.videoDeviceInput.device
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }
                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }
                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Can't lock device for configuration: \(error)")
            }
        }
    }

    func mayFocus(point: CGPoint) {
        if abs(self.focusPoint.x - point.x) <= 50 && abs(self.focusPoint.y - point.y) <= 50 {
            return
        }
        let oldPoint = self.focusPoint
        self.focusPoint = point
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: point)
        print("XXX: focus \(point) -> \(devicePoint) <- \(oldPoint)")
        //focus(with: .autoFocus, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
        focus(with: .locked, exposureMode: .autoExpose, at: devicePoint, monitorSubjectAreaChange: true)
    }
    
    func tenBitVariantOfFormat(activeFormat: AVCaptureDevice.Format) -> AVCaptureDevice.Format? {
        let formats = self.videoDeviceInput.device.formats
        let formatIndex = formats.firstIndex(of: activeFormat)!

        let activeDimensions = CMVideoFormatDescriptionGetDimensions(activeFormat.formatDescription)
        let activeMaxFrameRate = activeFormat.videoSupportedFrameRateRanges.last?.maxFrameRate
        let activePixelFormat = CMFormatDescriptionGetMediaSubType(activeFormat.formatDescription)
        
        if activePixelFormat != kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
            for index in formatIndex + 1..<formats.count {
                let format = formats[index]
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let maxFrameRate = format.videoSupportedFrameRateRanges.last?.maxFrameRate
                let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
                
                if activeMaxFrameRate != maxFrameRate || activeDimensions.width != dimensions.width || activeDimensions.height != dimensions.height {
                    break
                }
                if pixelFormat == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange {
                    return format
                }
            }
        } else {
            return activeFormat
        }
        return nil
    }
    
    private var selectedMovieMode10BitDeviceFormat: AVCaptureDevice.Format?
    
    private enum HDRVideoMode {
        case on
        case off
    }
    
    private var HDRVideoMode: HDRVideoMode = .on
    
    @IBOutlet private weak var HDRVideoModeButton: UIButton!
    
    @IBAction private func toggleHDRVideoMode(_ HDRVideoModeButton: UIButton) {
        sessionQueue.async {
            self.HDRVideoMode = (self.HDRVideoMode == .on) ? .off : .on
            let HDRVideMode = self.HDRVideoMode
            
            DispatchQueue.main.async {
                if HDRVideMode == .on {
                    do {
                        try self.videoDeviceInput.device.lockForConfiguration()
                        self.videoDeviceInput.device.activeFormat = self.selectedMovieMode10BitDeviceFormat!
                        self.videoDeviceInput.device.unlockForConfiguration()
                    } catch {
                        print("Can't lock device for configuration: \(error)")
                    }
                    self.HDRVideoModeButton.setTitle("HDR On", for: .normal)
                } else {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high
                    self.session.commitConfiguration()
                    self.HDRVideoModeButton.setTitle("HDR Off", for: .normal)
                }
            }
        }
    }
    
    private var movieOut: CaptureMovieFileOuptut?
    private var pointCloudOut: PointCloudRecorder?
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
    @IBOutlet private weak var recordButton: UIButton!
    @IBOutlet private weak var resumeButton: UIButton!
    
    private func getTmpNames() -> [String] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return [dir[0].appendingPathComponent(".tmp.0.mov").path, dir[0].appendingPathComponent(".tmp.1.mov").path]
    }
    
    private func getNextTmpName(name: String) -> String {
        let fns = getTmpNames()
        return name == fns[0] ? fns[1] : fns[0]
    }
    
    @IBAction private func record_stop(_ sender: Any) {
        if (movieOut?.isRecording ?? false) || pointCloudOut != nil {
            DispatchQueue.main.async {
                self.recordButton.isEnabled = false
                self.recordButton.setBackgroundImage(UIImage(systemName: "record.circle"), for: .normal)
                self.recordButton.tintColor = nil
            }
            sessionQueue.async {
                if self.movieOut != nil {
                    self.movieOut?.stop(completionHandler: self.onStopRecording)
                } else if self.pointCloudOut != nil {
                    self.pointCloudOut?.close()
                    self.pointCloudOut = nil
                    self.onStopRecording()
                }
            }
        } else {
            DispatchQueue.main.async {
                self.recordButton.isEnabled = true
                self.recordButton.setBackgroundImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
                self.recordButton.tintColor = .systemRed
            }

            if UIDevice.current.isMultitaskingSupported {
                self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            }
            var videoSettings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
            if videoOutput.availableVideoCodecTypes.contains(.hevc) {
                if videoSettings != nil {
                    videoSettings![AVVideoCodecKey] = AVVideoCodecType.hevc
                } else {
                    videoSettings = [AVVideoCodecKey:AVVideoCodecType.hevc]
                }
            }

            if self.ignoreOrientation,
               let orientation = previewView.videoPreviewLayer.connection?.videoOrientation,
               let isMirrored = previewView.videoPreviewLayer.connection?.isVideoMirrored {
                // MARK: this controls whether sample buffer is physically transformed to the video data output handler.
                if let connection = self.videoOutput.connection(with: .video) {
                    connection.videoOrientation = orientation
                }
                if let connection = self.depthDataOutput.connection(with: .depthData) {
                    connection.videoOrientation = orientation
                    connection.isVideoMirrored = isMirrored
                }
            }

            let audioSettings = audioOutput.recommendedAudioSettingsForAssetWriter(writingTo: .mov)

            // TODO: error handling
            try? FileManager.default.removeItem(at: self.tmpMovieUrl!)

            if sender as? UIButton == self.recordButton {
                self.movieOut = CaptureMovieFileOuptut()
                sessionQueue.async {
                    // TODO: error handling
                    let transform = self.ignoreOrientation ? CGAffineTransformIdentity : self.transform ?? CGAffineTransformIdentity
                    try? self.movieOut?.start(url: self.tmpMovieUrl!, videoSettings: videoSettings, transform: transform, audioSettings: audioSettings, location: self.locationManager.location)
                    self.onStartRecording()
                }
            } else {
                self.pointCloudOut = PointCloudRecorder()
                sessionQueue.async {
                    // TODO: error handling
                    if !(self.pointCloudOut?.open(self.tmpMovieUrl!.path, forWrite: true) ?? false) {
                        self.log("failed to start point cloud recording")
                        self.pointCloudOut?.close()
                        self.pointCloudOut = nil
                    }
                    self.onStartRecording()
                }
            }
        }
        return
    }

    // MARK: KeyValueObservattions & Notifications
    private var keyValueObservations = [NSKeyValueObservation]()
    
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }

            DispatchQueue.main.async {
//                self.cameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                // self.recordButton.isEnabled = isSessionRunning
            }
        }
        keyValueObservations.append(keyValueObservation)
        
        let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
            guard let systemPressureState = change.newValue else { return }
            self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
        }
        keyValueObservations.append(systemPressureStateObservation)
        
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError), name: .AVCaptureSessionRuntimeError, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted), name: .AVCaptureSessionWasInterrupted, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded), name: .AVCaptureSessionInterruptionEnded, object: session)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)
        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }
    
    @objc func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        print("Capture session runtime error: \(error)")
        
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            resumeButton.isHidden = false
        }
    }
    
    private func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
        let pressureLevel = systemPressureState.level
        if pressureLevel == .serious || pressureLevel == .critical {
            if (self.movieOut == nil || self.movieOut?.isRecording == false) && self.pointCloudOut == nil {
                do {
                    try self.videoDeviceInput.device.lockForConfiguration()
                    print("WARNING: Reached elevated system pressure level: \(pressureLevel). Throttling frame rate.")
                    self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                    self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                    self.videoDeviceInput.device.unlockForConfiguration()
                } catch {
                    print("Can't lock device for configuration: \(error)")
                }
            }
        } else if pressureLevel == .shutdown {
            print("Session stopped running due to shutdown system pressure level.")
        }
    }
    
    @objc func sessionWasInterrupted(notification: NSNotification) {
        if let movieOut = self.movieOut, movieOut.isRecording {
            sessionQueue.async {
                movieOut.stop(completionHandler: self.onStopRecording)
            }
        }
        if let pointCloudOut = self.pointCloudOut {
            sessionQueue.async {
                pointCloudOut.close()
                self.pointCloudOut = nil
                self.onStopRecording()
            }
        }

        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?, let reasonIntegerValue = userInfoValue.integerValue, let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            var showResumeButton = false
            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                showResumeButton = true
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                cameraUnavailableLabel.alpha = 0
                cameraUnavailableLabel.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1
                }
            } else if reason == .videoDeviceNotAvailableDueToSystemPressure {
                print("Session stopped running due to shutdown system pressure level.")
            }
            if showResumeButton {
                resumeButton.alpha = 0
                resumeButton.isHidden = false
                UIView.animate(withDuration: 0.25) {
                    self.resumeButton.alpha = 1
                }
            }
        }
    }
    
    @objc func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                self.resumeButton.alpha = 0
            }, completion: { _ in
                self.resumeButton.isHidden = true
            })
        }
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                self.cameraUnavailableLabel.alpha = 0
            }, completion: { _ in
                self.cameraUnavailableLabel.isHidden = true
            })
        }
    }
}

extension CaptureViewController {
    func setupMainMenu() {
        var options = [UIAction]()
        options.append(UIAction(title: self.textLogView.isHidden ? "Show Logs" : "Hide Logs", state: .off, handler: { item in
            self.textLogView.isHidden = !self.textLogView.isHidden
            self.setupMainMenu()
        }))
        var str: String
        switch self.gravityMode {
        case .none:
            str = "Gravity: None->Grid"
        case .grid:
            str = "Gravity: Grid->Axis"
        case .axis:
            str = "Gravity: Axis->Tilt"
        case .tilt:
            str = "Gravity: Tilt->None"
        }
        options.append(UIAction(title: str, state: .off, handler: {_ in
            switch self.gravityMode {
            case .none:
                self.gravityMode = .grid
                UserDefaults.standard.setValue("grid", forKey: "capture-gravity-mode")
            case .grid:
                self.gravityMode = .axis
                UserDefaults.standard.setValue("axis", forKey: "capture-gravity-mode")
            case .axis:
                self.gravityMode = .tilt
                UserDefaults.standard.setValue("tilt", forKey: "capture-gravity-mode")
            case .tilt:
                self.gravityMode = .none
                UserDefaults.standard.setValue("none", forKey: "capture-gravity-mode")
            }
            self.resetPreviewGravity()
            self.setupMainMenu()
        }))
        switch self.sceneViewMode {
        case 0:
            str = "Show Scene View"
        // case 1:
        //    str = "Maximize Scene View"
        default:
            str = "Hide Scene View"
        }
        options.append(UIAction(title: str, state: .off, handler: { item in
            self.toggleSceneViewMode()
            self.setupMainMenu()
        }))
        options.append(UIAction(title: self.freezePointCloud ? "Unfreeze Point Cloud" : "Freeze Point Cloud", state: .off, handler: { item in
            self.freezePointCloud = !self.freezePointCloud
            self.setupMainMenu()
        }))
        options.append(UIAction(title: self.showHeatmap ? "Disable Surface Heatmap" : "Show Surface Heatmap", state: .off, handler: { item in
            self.showHeatmap = !self.showHeatmap
            self.setupMainMenu()
        }))
#if false
        if self.cmdCapturePointCloud == 0 {
            str = "Start Point Cloud Capture"
        } else {
            str = "Stop Point Cloud Capture"
        }
        options.append(UIAction(title: str, state: .off, handler: { _ in
            self.togglePointCloudCapture()
            self.setupMainMenu()
        }))
        options.append(UIAction(title: "Capture a Point Cloud", state: .off, handler: { _ in
            self.captureOnePointCloud()
        }))
        options.append(UIAction(title: "Step Forward Point Cloud", state: .off, handler: { _ in
            self.stepPointCloud(forward: true)
        }))
        options.append(UIAction(title: "Step Backward Point Cloud", state: .off, handler: { _ in
            self.stepPointCloud(forward: false)
        }))
#endif
        if self.cmdCapturePointCloud == 0 {
            str = "Start Point Cloud Capture"
        } else {
            str = "Stop Point Cloud Capture"
        }
        options.append(UIAction(title: str, state: .off, handler: { _ in
            self.togglePointCloudCapture()
            self.setupMainMenu()
        }))
        if self.depthDataFilter {
            str = "Disable Depth Data Filter"
        } else {
            str = "Enable Depth Data Filter"
        }
        options.append(UIAction(title: str, state: .off, handler: { _ in
            self.depthDataFilter = !self.depthDataFilter
            self.setupMainMenu()
            self.sessionQueue.async {
                _ = self.selectCamera()
            }
        }))
#if true
        options.append(UIAction(title: "Reset Scene View", state: .off, handler: { _ in
            self.resetPointCloud()
        }))
#endif
        options.append(UIAction(title: (self.poser.logFunc == nil ? "Show" : "Hide") + " Movenet Score", state: .off, handler: { _ in
            self.poser.logFunc = self.poser.logFunc == nil ? self.log : nil
            self.setupMainMenu()
        }))

        let menu = UIMenu(title: "vipl", children: options)
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = menu
    }

    func setupCameraSelectionMenu() {
        let doit = {(action:UIAction) in
            if let cameras = CaptureHelper.listCameras(), let camera = cameras[action.title] {
                self.chosenCamera = camera
                UserDefaults.standard.set(camera.name, forKey: "the-camera")
            }
            self.sessionQueue.async {
                _ = self.selectCamera()
            }
        }
        
        var options = [UIAction]()
        if let choices = CaptureHelper.listCameras() {
            for name in choices.keys.sorted() {
                let item = UIAction(title: name, state: .off, handler: doit)
                options.append(item)
                if self.chosenCamera?.name == name {
                    item.state = .on
                }
            }
            if options.count == 0 {
                let item = UIAction(title: "no camera", state: .off, handler: {_ in })
                options.append(item)
            }
            if self.chosenCamera == nil {
                options[0].state = .on
                self.chosenCamera = choices[options[0].title]
            }
            let menu = UIMenu(title: "Cameras", options: .displayInline, children: options)
            camerasMenu.menu = menu
            if #available(iOS 15.0, *) {
                camerasMenu.changesSelectionAsPrimaryAction = true
            }
            camerasMenu.showsMenuAsPrimaryAction = true
        } else {
            camerasMenu.isHidden = true
        }
    }
    
    private func selectCamera() -> SessionSetupResult {
        self.selectedMovieMode10BitDeviceFormat = nil

        guard let chosenCamera = self.chosenCamera else { return .configurationFailed }
        session.beginConfiguration()
        if self.videoDeviceInput != nil {
            NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: self.videoDeviceInput.device)
            self.session.removeInput(self.videoDeviceInput)
        }

        let videoDeviceInput: AVCaptureDeviceInput!
        do {
            videoDeviceInput = try CaptureHelper.getCaptureDeviceInput(cam: chosenCamera)
        } catch {
            self.session.commitConfiguration()
            print("Cannot find camera: \(error.localizedDescription)")
            return .configurationFailed
        }

        if self.session.canAddInput(videoDeviceInput) {
            NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
            self.session.addInput(videoDeviceInput)
            self.videoDeviceInput = videoDeviceInput
        } else {
            self.session.addInput(self.videoDeviceInput)
        }

        let device = videoDeviceInput.device
        try? device.lockForConfiguration()
        device.activeFormat = chosenCamera.format
        device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(chosenCamera.frameRate))
        device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(chosenCamera.frameRate))
        if chosenCamera.depthDataFormat != nil {
            device.activeDepthDataFormat = chosenCamera.depthDataFormat
            device.activeDepthDataMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(chosenCamera.frameRate))
        }
        device.unlockForConfiguration()

        if let connection = self.videoOutput?.connection(with: .video) {
            self.selectedMovieMode10BitDeviceFormat = self.tenBitVariantOfFormat(activeFormat: self.videoDeviceInput.device.activeFormat)

            // TODO: HDR here?

            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }

        self.setupOutput(depthEnabled: chosenCamera.depthDataFormat != nil)
        session.commitConfiguration()
        self.setupSyncedOutputs(depthEnabled: chosenCamera.depthDataFormat != nil)

        DispatchQueue.main.async {
            self.recordButton.isEnabled = true

            if let connection = self.previewView.videoPreviewLayer.connection {
                (self.transform, self.reverseTransform) = self.getCaptureTransform(orientation: connection.videoOrientation, isMirrored: connection.isVideoMirrored, videoSettings: self.videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)!)
                self.isMirrored = connection.isVideoMirrored
                self.videoOutput?.connection(with: .video)?.videoOrientation = connection.videoOrientation

                if let depthDataConnection = self.depthDataOutput?.connection(with: .depthData) {
                    depthDataConnection.videoOrientation = connection.videoOrientation
                    depthDataConnection.isVideoMirrored = connection.isVideoMirrored
                }
            }
        }
        return .success
    }
}

extension CaptureViewController {
    @IBAction func dismissCapturedViewView(_ sender: Any) {
        guard let url = self.capturedMovieUrl else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        self.refreshCapturedVideoView()
    }

    @objc func tapCapturedVideoView(_ sender: UITapGestureRecognizer) {
        guard let controller = UIStoryboard(name: "PlayerView", bundle: nil).instantiateInitialViewController() as? PlayerViewController else { return }
        controller.loadViewIfNeeded()
        controller.modalPresentationStyle = .fullScreen
        controller.url = self.capturedMovieUrl
        present(controller, animated: true)
    }

    func refreshCapturedVideoView() {
        guard let url = self.capturedMovieUrl else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            self.capturedVideoView.isHidden = true

            // expand textLogView to the right
            self.textLogView.frame.size.width = view.bounds.width - (view.safeAreaInsets.left + view.safeAreaInsets.right)
            return
        }

        let thumbnail = CollectionViewController.getThumbnail(url: url)
        guard let thumbnail = thumbnail else { return }
        self.capturedVideoViewImg.frame.size = self.capturedVideoView.frame.size
        self.capturedVideoViewImg.frame.origin = CGPoint(x: 0, y: 0)
        self.capturedVideoViewImg.image = thumbnail

        let width, height: CGFloat
        if thumbnail.size.width < thumbnail.size.height {
            width = CGFloat(100)
            height = thumbnail.size.height * width / thumbnail.size.width
        } else {
            height = CGFloat(100)
            width = thumbnail.size.width * height / thumbnail.size.height
        }
        let x = self.view.frame.size.width - width
        let y = self.view.frame.size.height - height
        self.capturedVideoView.frame.size = CGSizeMake(width, height)
        self.capturedVideoView.frame.origin = CGPoint(x: x, y: y)
        self.capturedVideoViewImg.frame.size = self.capturedVideoView.frame.size
        self.capturedVideoViewImg.frame.origin = CGPoint(x: 0, y: 0)
        self.dismissCapturedVideoButton.frame.origin = CGPoint(x: self.capturedVideoView.frame.width - self.dismissCapturedVideoButton.frame.width, y: 0)
        self.capturedVideoView.isHidden = false

        // shrink textLogView to the left
        self.textLogView.frame.size.width = view.bounds.width - (view.safeAreaInsets.left + view.safeAreaInsets.right) - width
    }
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
    
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }

    func transform(width: CGFloat, height: CGFloat, mirrored: Bool = false) -> CGAffineTransform {
        switch self {
        case .portrait:
            return CGAffineTransform(0, 1, -1, 0, height, 0)
        case .portraitUpsideDown:
            return CGAffineTransform(0, -1, 1, 0, 0, width)
        case .landscapeLeft:
            if !mirrored {
                return CGAffineTransform(-1, 0, 0, -1, width, height)
            } else {
                return CGAffineTransformIdentity
            }
        case .landscapeRight:
            if !mirrored {
                return CGAffineTransformIdentity
            } else {
                return CGAffineTransform(-1, 0, 0, -1, width, height)
            }
        @unknown default:
            return CGAffineTransformIdentity
        }
    }

    func reverseTransform(width: Double, height: Double, mirrored: Bool = false) -> CGAffineTransform {
        switch self {
        case .portrait:
            if !mirrored {
                return CGAffineTransform(0, -1, 1, 0, 0, width)
            } else {
                return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: height, ty: width)
            }
        case .portraitUpsideDown:
            if !mirrored {
                return CGAffineTransform(0, 1, -1, 0, height, 0)
            } else {
                return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
            }
        case .landscapeLeft:
            if !mirrored {
                return CGAffineTransform(-1, 0, 0, -1, width, height)
            } else {
                return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0.0)
            }
        case .landscapeRight:
            if !mirrored {
                return CGAffineTransformIdentity
            } else {
                return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
            }
        @unknown default:
            return CGAffineTransformIdentity
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        return uniqueDevicePositions.count
    }
}

// video, audio, metadata output delegates
extension CaptureViewController {
    func getCaptureTransform(orientation: AVCaptureVideoOrientation, isMirrored: Bool, videoSettings: [String:Any]) -> (CGAffineTransform, CGAffineTransform) {
        guard let width = videoSettings[AVVideoWidthKey] as? Int32,
              let height = videoSettings[AVVideoHeightKey] as? Int32 else {
            return (CGAffineTransformIdentity, CGAffineTransformIdentity)
        }
        let transform = orientation.transform(width: CGFloat(width), height: CGFloat(height), mirrored: isMirrored)
        let reverseTransform = orientation.reverseTransform(width: CGFloat(width), height: CGFloat(height), mirrored: isMirrored)
        return (transform, reverseTransform)
    }

    private func onStartRecording() {
        DispatchQueue.main.async {
            self.recordButton.isEnabled = true
            self.recordButton.setBackgroundImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
            self.recordButton.tintColor = .systemRed
            self.durationLabel.isHidden = false
            self.durationLabel.text = "00:00"

            // timer during recording
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { timer in
                if let movieOut = self.movieOut {
                    if movieOut.isRecording {
                        let duration = CMTimeGetSeconds(movieOut.recordedDuration)
                        let minutes = Int(duration) / 60
                        let seconds = Int(duration) % 60
                        self.durationLabel.text = String(format: "%02d:%02d", minutes, seconds)
                    } else {
                        timer.invalidate()
                    }
                } else if let pointCloudOut = self.pointCloudOut {
                    let duration = pointCloudOut.recordedDuration()
                    let minutes = Int(duration) / 60
                    let seconds = Int(duration) % 60
                    self.durationLabel.text = String(format: "%02d:%02d", minutes, seconds)
                } else {
                    timer.invalidate()
                }
            })
        }
    }

    private func onStopRecording() {
        if let currentBackgroundRecordingID = self.backgroundRecordingID {
            self.backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
            if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
            }
        }
        let url: URL
        if PointCloudRecorder.isMovieFile(self.tmpMovieUrl!.path) {
            url = FileSystemHelper.getNextFileName(ext: "moz")!
        } else {
            url = FileSystemHelper.getNextFileName(ext: "mov")!
        }

        // update location
        if let tmpUrl = self.tmpMovieUrl {
            AVAsset.setMetadata(fileURL: tmpUrl, description: nil, location: self.locationManager.location) { success in
                // do nothing
            }
        }

        // TODO: error handling
        try? FileManager.default.moveItem(at: self.tmpMovieUrl!, to: url)
        self.capturedMovieUrl = url

        DispatchQueue.main.async {
            self.recordButton.isEnabled = true
            self.recordButton.setBackgroundImage(UIImage(systemName: "record.circle"), for: .normal)
            self.recordButton.tintColor = nil
            self.durationLabel.isHidden = true
            self.durationLabel.text = "00:00"
            self.refreshCapturedVideoView()
        }
    }

    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        if let videoData = synchronizedDataCollection.synchronizedData(for: self.videoOutput) as? AVCaptureSynchronizedSampleBufferData {
            if !videoData.sampleBufferWasDropped {
                self.movieOut?.append(videoData.sampleBuffer, for: .video, gravity: self.gravityView.gravityVector)

                if self.showPose {
                    if let lastTime = self.poserTime,
                       Date().timeIntervalSince(lastTime) < self.poserTimeThreshold {
                        // do nothing
                    } else {
                        self.poserTime = Date()
                        DispatchQueue.main.async {
                            let poser = self.poser
                            if let pixelBuffer = CMSampleBufferGetImageBuffer(videoData.sampleBuffer) {
                                var transform = self.reverseTransform
                                if self.ignoreOrientation {
                                    if !self.isMirrored {
                                        transform = CGAffineTransformIdentity
                                    } else {
                                        transform = CGAffineTransform(-1, 0, 0, 1, CGFloat(CVPixelBufferGetWidth(pixelBuffer)), 0)
                                    }
                                }
                                poser.runModel(assetId: nil, targetView: self.overlayView, pixelBuffer: pixelBuffer, transform: transform!, time: CMTime.zero, freeze: false) { (golfer) in
                                    let isRecording = (self.movieOut?.isRecording ?? false) || self.pointCloudOut != nil
                                    if isRecording {
                                        return
                                    }
                                    if let lastTime = self.useGestureTime,
                                       Date().timeIntervalSince(lastTime) < self.useGestureTimeThreshold {
                                        // do nothing
                                    } else {
                                        if let golfer = golfer,
                                           golfer.leftWrist.score >= 0.3 && golfer.leftElbow.score >= 0.3 && golfer.leftShoulder.score >= 0.3 && golfer.rightWrist.score >= 0.3 && golfer.rightElbow.score >= 0.3 && golfer.rightShoulder.score >= 0.3 &&
                                            self.isXMark(leftWrist: golfer.leftWrist.pt, leftElbow: golfer.leftElbow.pt, leftShoulder: golfer.leftShoulder.pt, rightWrist: golfer.rightWrist.pt, rightElbow: golfer.rightElbow.pt, rightShoulder: golfer.rightShoulder.pt) {
                                            DispatchQueue.main.async {
                                                self.record_stop(self.recordButton!)
                                                self.useGestureTime = Date()
                                                self.flashTorch(count: 2, millis: 100)
                                                print("X Mark")
                                            }
                                        }
                                    }
                                }

                                /* TODO: autofocus on found figure
                                 { (person) in
                                 guard let person = person else { return }
                                 var leftHip, rightHip: KeyPoint?
                                 for p in person.keyPoints {
                                 if p.bodyPart == .leftHip {
                                 leftHip = p
                                 } else if p.bodyPart == .rightHip {
                                 rightHip = p
                                 }
                                 }
                                 if let leftHip = leftHip,
                                 let rightHip = rightHip {
                                 let pt = CGPoint(x: (leftHip.coordinate.x + rightHip.coordinate.x), y: (leftHip.coordinate.y + rightHip.coordinate.y))
                                 DispatchQueue.main.async {
                                 self.mayFocus(point: pt)
                                 }
                                 }
                                 }
                                 */
                            }
                        }
                    }
                }
                if false /* self.showHands */ {
                    DispatchQueue.main.async {
                        let handPoseRequest = VNDetectHumanHandPoseRequest()
                        handPoseRequest.maximumHandCount = 5
                        if let pixelBuffer = CMSampleBufferGetImageBuffer(videoData.sampleBuffer) {
                            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
                            do {
                                try handler.perform([handPoseRequest])
                                for pose in handPoseRequest.results ?? [] {
                                    self.detectHandPose(pose)
                                }
                            } catch {
                                print("Failed to perform request: \(error.localizedDescription)")
                            }
                        }
                    }
                }
            }
        }

        if let audioData = synchronizedDataCollection.synchronizedData(for: self.audioOutput) as? AVCaptureSynchronizedSampleBufferData {
            if !audioData.sampleBufferWasDropped {
                self.movieOut?.append(audioData.sampleBuffer, for: .audio)
            }
        }

        if let syncedDepthData = synchronizedDataCollection.synchronizedData(for: self.depthDataOutput) as? AVCaptureSynchronizedDepthData,
           let videoData = synchronizedDataCollection.synchronizedData(for: self.videoOutput) as? AVCaptureSynchronizedSampleBufferData {
            if !syncedDepthData.depthDataWasDropped && !videoData.sampleBufferWasDropped {
                if self.pointCloudOut != nil {
                    self.appendPointCloud(depthData: syncedDepthData.depthData, pixelData: CMSampleBufferGetImageBuffer(videoData.sampleBuffer)!, time: CMSampleBufferGetPresentationTimeStamp(videoData.sampleBuffer))
                }
                if self.sceneViewMode != 0 {
                    self.showPointCloud(depthData: syncedDepthData.depthData, pixelData: CMSampleBufferGetImageBuffer(videoData.sampleBuffer)!, time: CMSampleBufferGetPresentationTimeStamp(videoData.sampleBuffer))
                }
            }
        }

        // if let syncedMetaData = synchronizedDataCollection.synchronizedData(for: metadataOutput) as? AVCaptureSynchronizedMetadataObjectData {
        //     var face: AVMetadataObject? = nil
        //     if let firstFace = syncedMetaData.metadataObjects.first {
        //         face = videoDataOutput.transformedMetadataObject(for: firstFace, connection: videoConnection)
        //     }
        // }
        return
    }

    // need to take care of video & audio
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output == self.videoOutput {
            self.movieOut?.append(sampleBuffer, for: .video)
/*
            DispatchQueue.main.async {
                let poser = self.poser
                let transform = CGAffineTransform(rotationAngle: .pi*3.0/2.0)
                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                    // convert pixelbuffer to kCVPixelFormatType_32BGRA
                    poser.runModel(assetId: nil, targetView: self.overlayView, pixelBuffer: pixelBuffer, transform: transform, time: CMTime.zero)
                }
            }
 */
        } else if output == self.audioOutput {
            self.movieOut?.append(sampleBuffer, for: .audio)
        }
        // won't be called
        //print("XXX: captureOutput, should not be called")
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // print("XXX: captureOutput, should not be called")
    }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didOutput depthData: AVDepthData, timestamp: CMTime, from connection: AVCaptureConnection) {
        // unused
        print("XXX: here?")
    }

    func depthDataOutput(_ output: AVCaptureDepthDataOutput, didDrop depthData: AVDepthData, timestamp: CMTime, from connection: AVCaptureConnection, reason: AVCaptureOutput.DataDroppedReason) {
        // unused
    }
}

// Movenet handler
extension CaptureViewController {
}

// point cloud stuff
extension CaptureViewController {
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

    func toggleSceneViewMode() {
        sceneViewMode = (sceneViewMode + 1) % 2
        refreshSceneView()
    }

    func refreshSceneView() {
        let sliderHeight = CGFloat(40), sliderMargin = CGFloat(0)

        switch sceneViewMode {
        case 0:     // hidden
            self.sceneView.isHidden = true
            self.rangeSlider.isHidden = true
            self.previewView.isHidden = false
        /*
        case 1:     // 1/3 size, record mode
            self.sceneView.isHidden = false
            self.rangeSlider.isHidden = true
            if view.bounds.width < view.bounds.height {
                self.sceneView.frame.size.width = view.bounds.width * 2 / 5
                self.sceneView.frame.size.height = view.bounds.height * self.sceneView.frame.size.width / view.bounds.width
            } else {
                self.sceneView.frame.size.height = view.bounds.height * 2 / 5
                self.sceneView.frame.size.width = view.bounds.width * self.sceneView.frame.size.height / view.bounds.height
            }
            self.sceneView.frame.origin.y = self.xButton.frame.origin.y + self.xButton.frame.height
            self.sceneView.frame.origin.x = view.frame.width - view.safeAreaInsets.right - self.sceneView.frame.width
         */
        default:    // full size, play mode
            self.sceneView.isHidden = false
            self.rangeSlider.isHidden = true
            self.sceneView.frame.origin = CGPoint(x: 0, y: 0)
            self.sceneView.frame.size = self.previewView.frame.size
            self.previewView.isHidden = true
        }

        let x = self.sceneView.frame.origin.x + CGFloat(sliderMargin)
        let y = self.sceneView.frame.origin.y + self.sceneView.frame.size.height - sliderHeight
        self.rangeSlider.frame = CGRect(x: x, y: y, width: self.sceneView.frame.size.width - CGFloat(2 * sliderMargin), height: CGFloat(sliderHeight))
    }

    func resetPointCloud() {
        DispatchQueue.main.async {
            self.pointClouds?.clear()
            self.pointClouds?.showFrame()
        }
    }

    func togglePointCloudCapture() {
        if self.movieOut != nil {
            return
        } else if let pointCloudOut = self.pointCloudOut {
            pointCloudOut.close()
            self.pointCloudOut = nil
            self.onStopRecording()
        } else {
            record_stop("start")
        }
#if false
        if self.cmdCapturePointCloud == 0 {
            pointClouds?.startRecording()
            self.cmdCapturePointCloud = 1
            self.durationLabel.isHidden = false
        } else {
            pointClouds?.stopRecording()
            self.cmdCapturePointCloud = 0
            self.durationLabel.isHidden = true
            self.stepPointCloud(forward: true)
            self.rangeSlider.min = 0
            self.rangeSlider.lowerBound = 0
            self.rangeSlider.max = CGFloat((pointClouds?.count ?? 1) - 1)
            self.rangeSlider.upperBound = self.rangeSlider.max
            self.rangeSlider.thumb = 0
        }
#endif
    }

    func captureOnePointCloud() {
        if self.cmdCapturePointCloud == 0 {
            pointClouds?.startRecording()
        }
        self.durationLabel.isHidden = true
        self.cmdCapturePointCloud = 2
    }

    func stepPointCloud(forward: Bool) {
        guard let pointClouds = self.pointClouds else { return }
        if forward {
            (_, _) = pointClouds.seek(frame: pointClouds.currentFrame+1)
        } else {
            (_, _) = pointClouds.seek(frame: pointClouds.currentFrame-1)
        }
        DispatchQueue.main.async {
            let frame = pointClouds.currentFrame
            let count = pointClouds.count
            let duration = pointClouds.duration
            pointClouds.showFrame()
            self.log("\(frame)/\(count) \(duration.toDurationString(withSubSeconds: true))")
        }
    }

    func appendPointCloudOld(depthData: AVDepthData, pixelBuffer: CVPixelBuffer, time: CMTime) {
        guard let pointClouds = self.pointClouds,
              let ptcld = PointCloud2.capture(depthData: depthData, colors: self.isMirrored ? pixelBuffer.mirrored()! : pixelBuffer) else {
            return
        }
        pointClouds.append(item: ptcld, time: time)
        let showPointCloud = self.cmdCapturePointCloud == 2
        if self.cmdCapturePointCloud == 2 {
            self.cmdCapturePointCloud = 0
        }
        DispatchQueue.main.async {
            let count = pointClouds.count
            let duration = pointClouds.duration
            if showPointCloud {
                pointClouds.showFrame()
                self.rangeSlider.min = 0
                self.rangeSlider.lowerBound = 0
                self.rangeSlider.max = CGFloat(pointClouds.count-1)
                self.rangeSlider.upperBound = self.rangeSlider.max
                self.rangeSlider.thumb = CGFloat(pointClouds.count-1)
            }
            self.durationLabel.text = "\(count) \(duration.toDurationString(withSubSeconds: false))"
            self.log(self.durationLabel.text!)
        }
    }

    func appendPointCloud(depthData: AVDepthData, pixelData: CVPixelBuffer, time: CMTime) {
        guard let pointCloudOut = self.pointCloudOut else { return }
        var pixels, depths: CVPixelBuffer
        pixels = pixelData
        depths = depthData.depthDataMap
        if pixels.size.width != depths.size.width {
            depths = resizePixelBuffer(depths, width: Int(pixels.size.width), height: Int(pixels.size.height))!
        }
        if self.isMirrored {
            depths = depths.mirrored()!
        }
        guard var depths = depths.toFloats(),
              var colors = pixels.toBytes(),
              let cameraCalibrationData = depthData.cameraCalibrationData else { return }
        let width = CVPixelBufferGetWidth(pixels)
        let height = CVPixelBufferGetHeight(pixels)
        var gravity: [Float]?
        if let g = self.gravity {
            gravity = [Float(g.x), Float(g.y), Float(g.z)]
        }
        let info = PointCloud.getFrameCalibrationInfo(calibrationData: cameraCalibrationData, width: width, height: height, camera: nil, gravity: gravity)
        let jsonInfo = info.toJson()

        pointCloudOut.record(time.seconds, info: jsonInfo, count: Int32(width * height), depths: &(depths), colors: &(colors))
    }

    func showPointCloud(depthData: AVDepthData, pixelData: CVPixelBuffer, time: CMTime) {
        if self.freezePointCloud {
            return
        }
        if self.ptcldSem.wait(timeout: .now()) != .success {
            return
        }

        // for now for truedepth camera
        var gravity = self.gravity
        if self.isMirrored {
            PointCloud2.interlace = 2
            if gravity != nil {
                gravity!.z = -gravity!.z
            }
        } else {
            PointCloud2.interlace = 1
        }

        guard let ptcld = PointCloud2.capture(depthData: depthData, colors: self.isMirrored ? pixelData.mirrored()! : pixelData, gravity: gravity),
              let node = ptcld.toSCNNode(heatmap: self.showHeatmap) else { return }
        DispatchQueue.main.async {
            if let node = self.sceneView.scene?.rootNode.childNodes.first(where: { node in return
                node.name == "it"}) {
                node.removeFromParentNode()
            }
            node.name = "it"
            self.sceneView.scene?.rootNode.addChildNode(node)
            self.ptcldSem.signal()
        }
    }

    @objc func rangeSliderValueChanged(_ rangeSlider: RangeSlider) {
        if self.pointClouds?.isRecording ?? true {
            return
        }
        switch rangeSlider.active {
        case .thumb:
            let ix = Int(rangeSlider.thumb)
            _ = self.pointClouds?.seek(frame: ix)
            self.pointClouds?.showFrame()
        default:
            break
        }
    }
}

extension CaptureViewController {

    func detectHandPose(_ observation: VNHumanHandPoseObservation) {
        // Extract points for each finger
        guard let thumbTip = try? observation.recognizedPoint(.thumbTip),
              let thumbIP = try? observation.recognizedPoint(.thumbIP),
              let thumbMP = try? observation.recognizedPoint(.thumbMP),
              let indexTip = try? observation.recognizedPoint(.indexTip),
              let indexPIP = try? observation.recognizedPoint(.indexPIP),
              let middleTip = try? observation.recognizedPoint(.middleTip),
              let middlePIP = try? observation.recognizedPoint(.middlePIP),
              let ringTip = try? observation.recognizedPoint(.ringTip),
              let ringPIP = try? observation.recognizedPoint(.ringPIP),
              let littleTip = try? observation.recognizedPoint(.littleTip),
              let littlePIP = try? observation.recognizedPoint(.littlePIP) else {
            return
        }

        // Calculate angles for better distinction
        let thumbAngle = angleBetweenPoints(point1: thumbMP.location, point2: thumbIP.location, point3: thumbTip.location)
        let indexAngle = angleBetweenPoints(point1: thumbMP.location, point2: indexPIP.location, point3: indexTip.location)
        let rect = boundingRectangle(points: [thumbTip.location, indexTip.location, middleTip.location, ringTip.location, littleTip.location])
        let ratio = rect.height / (rect.width == 0 ? 1 : rect.width)

        print("XXX: \(thumbAngle) \(indexAngle) \(ratio)")

        // Check for thumbs up gesture
        if ratio > 2.0 && thumbAngle > 150 && thumbTip.location.y > thumbMP.location.y {
            flashTorch(count: 3, millis: 50)
            print("Thumbs Up \(thumbAngle) \(indexAngle)")
        }

        // Check for thumbs down gesture
        if ratio > 2.0 && thumbAngle > 150 && thumbTip.location.y < thumbMP.location.y {
            flashTorch(count: 2, millis: 100)
            print("Thumbs Down \(thumbAngle) \(indexAngle)")
        }
    }

    func boundingRectangle(points: [CGPoint]) -> CGRect {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = CGFloat.leastNormalMagnitude
        var maxY = CGFloat.leastNormalMagnitude

        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        let width = maxX - minX
        let height = maxY - minY

        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    func angleBetweenPoints(point1: CGPoint, point2: CGPoint, point3: CGPoint) -> CGFloat {
        let v1 = CGVector(dx: point1.x - point2.x, dy: point1.y - point2.y)
        let v2 = CGVector(dx: point3.x - point2.x, dy: point3.y - point2.y)
        let angle = atan2(v2.dy, v2.dx) - atan2(v1.dy, v1.dx)
        return abs(angle) * 180 / .pi
    }

    // Helper function to calculate the angle between three points
    func angleBetweenPoints2(point1: CGPoint, point2: CGPoint, point3: CGPoint) -> CGFloat {
        let v1 = CGVector(dx: point1.x - point2.x, dy: point1.y - point2.y)
        let v2 = CGVector(dx: point3.x - point2.x, dy: point3.y - point2.y)
        let angle = atan2(v2.dy, v2.dx) - atan2(v1.dy, v1.dx)

        // Normalize angle to [0, 2 * pi]
        var normalizedAngle = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if normalizedAngle < 0 {
            normalizedAngle += 2 * .pi
        }

        return normalizedAngle * 180 / .pi
    }

    func processHandPose(_ observation: VNHumanHandPoseObservation) {
        // Extract hand joint locations
        guard let thumbTip = try? observation.recognizedPoint(.thumbTip),
              let thumbIP = try? observation.recognizedPoint(.thumbIP),
              let thumbMP = try? observation.recognizedPoint(.thumbMP),
              let indexTip = try? observation.recognizedPoint(.indexTip),
              let indexDIP = try? observation.recognizedPoint(.indexDIP),
              let indexPIP = try? observation.recognizedPoint(.indexPIP),
              let middleTip = try? observation.recognizedPoint(.middleTip),
              let middleDIP = try? observation.recognizedPoint(.middleDIP),
              let middlePIP = try? observation.recognizedPoint(.middlePIP),
              let ringTip = try? observation.recognizedPoint(.ringTip),
              let ringPIP = try? observation.recognizedPoint(.ringPIP),
              let littleTip = try? observation.recognizedPoint(.littleTip),
              let littlePIP = try? observation.recognizedPoint(.littlePIP) else {
            return
        }

        /*
        // Check for OK sign
        if thumbTip.location.distance(to: indexPIP.location) < 0.1 && indexDIP.location.y < indexPIP.location.y {
            print("OK Sign")
        }

        // Check for V sign
        if indexDIP.location.y < indexPIP.location.y && middleDIP.location.y < middlePIP.location.y &&
            indexTip.location.distance(to: middleTip.location) > 0.1 && thumbIP.location.y > thumbTip.location.y {
            print("V Sign")
        }

        // Check for Peace sign
        if indexDIP.location.y < indexPIP.location.y && middleDIP.location.y < middlePIP.location.y &&
            ringTip.location.y > middleTip.location.y && littleTip.location.y > middleTip.location.y {
            print("Peace Sign")
        }

        // Check for ILY sign
        if thumbIP.location.y > thumbTip.location.y && indexDIP.location.y < indexPIP.location.y &&
            middleDIP.location.y < middlePIP.location.y && ringTip.location.y > middleTip.location.y &&
            littleTip.location.y > middleTip.location.y {
            print("ILY Sign")
        }
         */

        // Check for thumbs up gesture
        if thumbTip.location.y > thumbIP.location.y && thumbTip.location.y > thumbMP.location.y {
            let fingersCurled = indexTip.location.y < indexPIP.location.y &&
                                middleTip.location.y < middlePIP.location.y &&
                                ringTip.location.y < ringPIP.location.y &&
                                littleTip.location.y < littlePIP.location.y

            if fingersCurled {
                print("Thumbs Up")
            }
        }

        // Check for thumbs down gesture
        if thumbTip.location.y < thumbIP.location.y && thumbTip.location.y < thumbMP.location.y {
            let fingersExtended = indexTip.location.y > indexPIP.location.y &&
            middleTip.location.y > middlePIP.location.y &&
            ringTip.location.y > ringPIP.location.y &&
            littleTip.location.y > littlePIP.location.y

            if fingersExtended {
                print("Thumbs Down")
            }
        }

        /*
        // Check for Thumbs Up
        if thumbIP.location.y > thumbTip.location.y && indexTip.location.y > indexPIP.location.y &&
            middleTip.location.y > middlePIP.location.y && ringTip.location.y > middleTip.location.y &&
            littleTip.location.y > middleTip.location.y {
            print("Thumbs Up")
        }

        // Check for thumbs down gesture
        if thumbTip.location.y < thumbIP.location.y &&
            indexTip.location.y > indexPIP.location.y {
            print("Thumbs Down")
        }
         */
    }

    func flashTorch(count: Int, millis: Int) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }

        let interval: TimeInterval = Double(millis) / 1000.0
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval * TimeInterval(2 * i)) {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = .on
                    try device.setTorchModeOn(level: 0.1)
                    device.unlockForConfiguration()
                } catch {
                    print("Error turning on flashlight: \(error)")
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + interval * TimeInterval(2 * i + 1)) {
                do {
                    try device.lockForConfiguration()
                    device.torchMode = .off
                    device.unlockForConfiguration()
                } catch {
                    print("Error turning off flashlight: \(error)")
                }
            }
        }
    }

    func isXMark(leftWrist: CGPoint, leftElbow: CGPoint, leftShoulder: CGPoint, rightWrist: CGPoint, rightElbow: CGPoint, rightShoulder: CGPoint) -> Bool {
        let shoulderDist = euclideanDistance(leftShoulder, rightShoulder)
        let wristDist = euclideanDistance(leftWrist, rightWrist)
        let xMinShoulder = min(leftShoulder.x, rightShoulder.x)
        let xMaxShoulder = max(leftShoulder.x, rightShoulder.x)

        return xMinShoulder < leftWrist.x && leftWrist.x < xMaxShoulder && xMinShoulder < rightWrist.x && rightWrist.x < xMaxShoulder && abs(leftShoulder.x - leftElbow.x) < abs(leftShoulder.x - leftWrist.x) && abs(rightShoulder.x - rightElbow.x) < abs(rightShoulder.x - rightWrist.x) && min(leftWrist.y, rightWrist.y) < max(leftElbow.y, rightElbow.y) && shoulderDist > wristDist * 3
    }

    func euclideanDistance(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        return sqrt(pow(point1.x - point2.x, 2) + pow(point1.y - point2.y, 2))
    }
}

// logging to UITextView
extension CaptureViewController {
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

extension CaptureViewController {
    func initGravityView() {
        // Check if accelerometer data is available
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.02
            motionManager.startDeviceMotionUpdates(to: .main) { (data, error) in
                if let validData = data {
                    // Update the vector view
                    DispatchQueue.main.async {
                        self.setPreviewGravity(gravity: validData.gravity)
                    }
                }
            }
        }
    }

    func resetPreviewGravity() {
        DispatchQueue.main.async {
            switch self.gravityMode {
            case .none, .tilt:
                self.gravityView.isHidden = true
                self.previewView.layer.transform = CATransform3DIdentity
            case .grid, .axis:
                self.gravityView.isHidden = false
                self.previewView.layer.transform = CATransform3DIdentity
            }
            if let gravity = self.gravity {
                self.setPreviewGravity(gravity: gravity)
            }
        }
    }

    func setPreviewGravity(gravity: CMAcceleration) {
        self.gravity = gravity
        DispatchQueue.main.async {
            switch self.gravityMode {
            case .none:
                self.gravityView.isHidden = true
                self.gravityView.update(gravity: gravity, reverse: false)
            case .grid:
                self.gravityView.isHidden = false
                self.gravityView.update(gravity: gravity, reverse: false)
            case .axis, .tilt:
                self.gravityView.isHidden = self.gravityMode == .tilt
                self.gravityView.update(gravity: gravity, reverse: true)

                var gx = Double(0), gy = Double(0), gz = Double(0)
                    gz = gravity.z
                switch self.windowOrientation {
                case .portrait, .unknown:
                    gx = gravity.x
                    gy = gravity.y
                case .portraitUpsideDown:
                    gx = gravity.x
                    gy = -gravity.y
                case .landscapeLeft:
                    gx = gravity.y
                    gy = -gravity.x
                case .landscapeRight:
                    gx = -gravity.y
                    gy = gravity.x
                @unknown default:
                    fatalError()
                }

                let pitch = atan2(-gy, gx) - .pi / 2.0
                let roll = atan2(gy, gz) + .pi / 2.0

                var transform = CATransform3DIdentity
                transform = CATransform3DRotate(transform, -pitch, 0, 0, 1) // Rotate around Z axis for pitch
                transform = CATransform3DRotate(transform, -roll, 1, 0, 0)  // Rotate around X axis for roll
                self.previewView.layer.transform = transform
            }
        }
    }
}

extension CaptureViewController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // print("XXX: didUpdateLocations: \(locations)")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // print("XXX: true: \(newHeading.trueHeading), magnetic: \(newHeading.magneticHeading)")
        let northDirection = newHeading.magneticHeading
        DispatchQueue.main.async {
            switch self.gravityMode {
            case .none:
                self.gravityView.isHidden = true
                self.gravityView.update(north: northDirection, reverse: false)
            case .grid:
                self.gravityView.isHidden = false
                self.gravityView.update(north: northDirection, reverse: false)
            case .axis, .tilt:
                self.gravityView.isHidden = self.gravityMode == .tilt
                self.gravityView.update(north: northDirection, reverse: true)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Capture: location manager didFailWithError: \(error)")
    }
}
