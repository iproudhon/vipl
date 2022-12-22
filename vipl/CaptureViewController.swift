//
//  CaptureViewController.swift
//  vipl
//
//  Created by Steve H. Jung on 12/14/22.
//

import AVFoundation
import CoreLocation
import Photos
import AVKit
import UIKit
import MobileCoreServices

class CaptureViewController: UIViewController, AVCaptureFileOutputRecordingDelegate {
    
    private var spinner: UIActivityIndicatorView!
    
    var windowOrientation: UIInterfaceOrientation {
        return view.window?.windowScene?.interfaceOrientation ?? .unknown
    }
    
    let locationManager = CLLocationManager()
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private let session = AVCaptureSession()
    private var isSessionRunning = false
    private var selectedSemanticSegmentationMatteTypes = [AVSemanticSegmentationMatte.MatteType]()
    
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var setupResult: SessionSetupResult = .success
    
    private var chosenCamera: CaptureCameraType?
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    
    @IBOutlet private weak var previewView: CapturePreviewView!
    @IBOutlet private weak var camerasMenu: UIButton!
    
    private let rangeSlider = RangeSlider(frame: .zero)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // TODO: initialize UI here
        setupCameraSelectionMenu()

        // initialize the range slider
        view.addSubview(rangeSlider)
        rangeSlider.addTarget(self, action: #selector(rangeSliderValueChanged(_:)),
                              for: .valueChanged)
        
        // TODO: setup the video preview view
        previewView.session = session
        
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
    }

    override func viewWillDisappear(_ animated: Bool) {
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
                self.removeObservers()
            }
        }
        super.viewWillDisappear(animated)
    }
    
    override func viewDidLayoutSubviews() {
        let margin: CGFloat = 40
        let width = view.bounds.width - 2 * margin
        let height: CGFloat = 30

        let x = (view.bounds.width - width) / 2
        let y = (view.bounds.height - height * 2)
        rangeSlider.frame = CGRect(x: x, y: y, width: width, height: height)
    }
    
    override var shouldAutorotate: Bool {
        if let movieFileOutput = movieFileOutput {
            return !movieFileOutput.isRecording
        }
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        if let videoPreviewLayerConnection = previewView.videoPreviewLayer.connection {
            let deviceOrientation = UIDevice.current.orientation
            guard let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation), deviceOrientation.isPortrait || deviceOrientation.isLandscape else {
                return
            }
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }
    }

    private func configureSession() {
        if setupResult != .success {
            return
        }
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        // video input device
        do {
            /*
            var defaultVideoDevice: AVCaptureDevice?

            if let dualCameraDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
                defaultVideoDevice = dualCameraDevice
            } else if let dualWideCameraDevice = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                defaultVideoDevice = dualWideCameraDevice
            } else if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                defaultVideoDevice = frontCameraDevice
            }
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device not found")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
*/
            guard let videoDeviceInput = getCamera() else {
                print("Default video device not found")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput

                DispatchQueue.main.async {
                    var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                    if self.windowOrientation != .unknown {
                        if let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: self.windowOrientation) {
                            initialVideoOrientation = videoOrientation
                        }
                    }
                    self.previewView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
                }
            } else {
                print("Can't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Can't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

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
        setupOutput()
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
    
    private func setupOutput() {
        sessionQueue.async {
            let movieFileOutput = AVCaptureMovieFileOutput()
            if self.session.canAddOutput(movieFileOutput) {
                self.session.beginConfiguration()
                self.session.addOutput(movieFileOutput)
                self.session.sessionPreset = .high

                self.selectedMovieMode10BitDeviceFormat = self.tenBitVariantOfFormat(activeFormat: self.videoDeviceInput.device.activeFormat)
                
                if self.selectedMovieMode10BitDeviceFormat != nil {
                    DispatchQueue.main.async {
                        self.HDRVideoModeButton.isHidden = false
                        self.HDRVideoModeButton.isEnabled = true
                    }
                    if self.HDRVideoMode == .on {
                        do {
                            try self.videoDeviceInput.device.lockForConfiguration()
                            self.videoDeviceInput.device.activeFormat = self.selectedMovieMode10BitDeviceFormat!
                            self.videoDeviceInput.device.unlockForConfiguration()
                        } catch {
                            print("Can't lock device for configuration: \(error)")
                        }
                    }
                }
                if let connection = movieFileOutput.connection(with: .video) {
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }
                self.session.commitConfiguration()
                self.movieFileOutput = movieFileOutput
                    
                DispatchQueue.main.async {
                    self.recordButton.isEnabled = true
                }
            }
        }
    }
    
    @IBOutlet private weak var cameraButton: UIButton!
    @IBOutlet private weak var cameraUnavailableLabel: UILabel!
    @IBOutlet private weak var durationLabel: UILabel!
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera, .builtInDualWideCamera], mediaType: .video, position: .unspecified)
    
    @IBAction private func changeCamera(_ cameraButton: UIButton) {
        // TODO: UI elements
        
        self.selectedMovieMode10BitDeviceFormat = nil
        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position
            
            let backVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .back)
            let frontVideoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInWideAngleCamera], mediaType: .video, position: .front)
            
            var newVideoDevice: AVCaptureDevice? = nil
            switch currentPosition {
            case .unspecified, .front:
                newVideoDevice = backVideoDeviceDiscoverySession.devices.first
            case .back:
                newVideoDevice = frontVideoDeviceDiscoverySession.devices.first
            @unknown default:
                newVideoDevice = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    self.session.beginConfiguration()
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    if let connection = self.movieFileOutput?.connection(with: .video) {
                        self.session.sessionPreset = .high
                        self.selectedMovieMode10BitDeviceFormat = self.tenBitVariantOfFormat(activeFormat: self.videoDeviceInput.device.activeFormat)
                        if self.selectedMovieMode10BitDeviceFormat != nil {
                            DispatchQueue.main.async {
                                self.HDRVideoModeButton.isEnabled = true
                            }
                            if self.HDRVideoMode == .on {
                                do {
                                    try self.videoDeviceInput.device.lockForConfiguration()
                                    self.videoDeviceInput.device.activeFormat = self.selectedMovieMode10BitDeviceFormat!
                                    print("Setting 'x420' format \(String(describing: self.selectedMovieMode10BitDeviceFormat)) for video recording")
                                    self.videoDeviceInput.device.unlockForConfiguration()
                                } catch {
                                    print("Can't lock device for configuration: \(error)")
                                }
                            }
                        }
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
            // TODO: UI elements
            DispatchQueue.main.async {
            }
        }
    }
    
    @IBAction private func focusAndExposeTap(_ gestureRecognizer: UITapGestureRecognizer) {
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: gestureRecognizer.location(in: gestureRecognizer.view))
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
    
    private var movieFileOutput: AVCaptureMovieFileOutput?
    
    private var backgroundRecordingID: UIBackgroundTaskIdentifier?
    
    @IBOutlet private weak var recordButton: UIButton!
    @IBOutlet private weak var resumeButton: UIButton!
    
    @IBAction private func toggleMovieRecording(_ recordButton: UIButton) {
        guard let movieFileOutput = self.movieFileOutput else { return }
        
        // TODO: UI elements
        
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        sessionQueue.async {
            if !movieFileOutput.isRecording {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                
                let movieFileOutputConnection = movieFileOutput.connection(with: .video)
                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation!
                
                let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
                if availableVideoCodecTypes.contains(.hevc) {
                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                }

                // TODO: recording to a temporary file
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
            } else {
                movieFileOutput.stopRecording()
            }
        }
    }
    
    private func getTmpNames() -> [String] {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return [dir[0].appendingPathComponent(".tmp.0.mov").path, dir[0].appendingPathComponent(".tmp.1.mov").path]
    }
    
    private func getNextTmpName(name: String) -> String {
        let fns = getTmpNames()
        return name == fns[0] ? fns[1] : fns[0]
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
    
    @IBAction private func record_stop(_ sender: Any) {
        guard let movieFileOutput = self.movieFileOutput else { return }
        
        let videoPreviewLayerOrientation = previewView.videoPreviewLayer.connection?.videoOrientation
        sessionQueue.async {
            if movieFileOutput.isRecording {
                movieFileOutput.stopRecording()
            } else {
                if UIDevice.current.isMultitaskingSupported {
                    self.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                }
                let movieFileOutputConnection = movieFileOutput.connection(with: .video)
                movieFileOutputConnection?.videoOrientation = videoPreviewLayerOrientation!
                
                let availableVideoCodecTypes = movieFileOutput.availableVideoCodecTypes
                if availableVideoCodecTypes.contains(.hevc) {
                    movieFileOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: movieFileOutputConnection!)
                }
                
                // TODO: record to own directory
                let fn = self.getNextFileName()
                movieFileOutput.startRecording(to: URL(fileURLWithPath: fn), recordingDelegate: self)
                
                /*
                let outputFileName = NSUUID().uuidString
                let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
                movieFileOutput.startRecording(to: URL(fileURLWithPath: outputFilePath), recordingDelegate: self)
                 */
            }
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.recordButton.isEnabled = true
            self.recordButton.setBackgroundImage(UIImage(systemName: "stop.circle.fill"), for: .normal)
            self.durationLabel.isHidden = false
            self.durationLabel.text = "00:00"
            
            // timer during recording
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { timer in
                if let movieFileOutput = self.movieFileOutput {
                    if movieFileOutput.isRecording {
                        let duration = CMTimeGetSeconds(movieFileOutput.recordedDuration)
                        let minutes = Int(duration) / 60
                        let seconds = Int(duration) % 60
                        self.durationLabel.text = String(format: "%02d:%02d", minutes, seconds)
                    } else {
                        timer.invalidate()
                    }
                } else {
                    timer.invalidate()
                }
            })
        }
    }
    
    func fileOutput2Photo(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
        func cleanup() {
            let path = outputFileURL.pathExtension
            if FileManager.default.fileExists(atPath: path) {
                do {
                    try FileManager.default.removeItem(atPath: path)
                } catch {
                    print("Can't remove file at url: \(outputFileURL)")
                }
            }
            
            if let currentBackgroundRecordingID = backgroundRecordingID {
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
                if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                    UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
                }
            }
        }
        
        var success = true
        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }
        if success {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: outputFileURL, options: options)
                        creationRequest.location = self.locationManager.location
                    }, completionHandler: { success, error in
                        if !success {
                            print("<XXX> can't save the movie to your photo library: \(String(describing: error))")
                        }
                        cleanup()
                    })
                } else {
                    cleanup()
                }
            }
        } else {
            cleanup()
        }
    }
        
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let currentBackgroundRecordingID = backgroundRecordingID {
            backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
            if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID)
            }
        }

        var success = true
        if error != nil {
            print("Movie file finishing error: \(String(describing: error))")
            success = (((error! as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as AnyObject).boolValue)!
        }

        DispatchQueue.main.async {
            self.recordButton.isEnabled = true
            self.recordButton.setBackgroundImage(UIImage(systemName: "record.circle"), for: .normal)
            self.durationLabel.isHidden = true
            self.durationLabel.text = "00:00"
        }
    }
    
    // MARK: KeyValueObservattions & Notifications
    private var keyValueObservations = [NSKeyValueObservation]()
    
    private func addObservers() {
        let keyValueObservation = session.observe(\.isRunning, options: .new) { _, change in
            guard let isSessionRunning = change.newValue else { return }

            DispatchQueue.main.async {
//                self.cameraButton.isEnabled = isSessionRunning && self.videoDeviceDiscoverySession.uniqueDevicePositionsCount > 1
                self.recordButton.isEnabled = isSessionRunning && self.movieFileOutput != nil
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
            if self.movieFileOutput == nil || self.movieFileOutput?.isRecording == false {
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
    class CaptureCameraType {
        var name: String
        var deviceType: AVCaptureDevice.DeviceType
        var position: AVCaptureDevice.Position
        var format: AVCaptureDevice.Format
        var frameRate: Float64
        var dimensions: CMVideoDimensions
        
        init(name: String, deviceType: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position, format: AVCaptureDevice.Format, frameRate: Float64, dimensions: CMVideoDimensions) {
            self.name = name
            self.deviceType = deviceType
            self.position = position
            self.format = format
            self.frameRate = frameRate
            self.dimensions = dimensions
        }
    }
    
    func listCameras() -> [String:CaptureCameraType]? {
        var session: AVCaptureDevice.DiscoverySession?
        if #available(iOS 15.4, *) {
            session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .builtInTrueDepthCamera, .builtInLiDARDepthCamera], mediaType: .video, position: .unspecified)
        } else {
            session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified)
        }
        
        var choices: [String:CaptureCameraType] = [:]
        guard let session = session else { return nil }
        for device in session.devices {
            // frameRate -> format
            var rate2format: [Float64:AVCaptureDevice.Format] = [:]
            for format in device.formats {
                let dims = format.formatDescription.dimensions
                for range in format.videoSupportedFrameRateRanges {
                    if let ofmt = rate2format[range.maxFrameRate] {
                        let odims = ofmt.formatDescription.dimensions
                        if dims.height > odims.height || dims.width > odims.width {
                            rate2format.updateValue(format, forKey: range.maxFrameRate)
                        }
                    } else {
                        rate2format[range.maxFrameRate] = format
                    }
                }
            }
            
            for key in rate2format.keys.sorted() {
                guard let format = rate2format[key] as AVCaptureDevice.Format? else { continue }
                let dims = format.formatDescription.dimensions
                let name = "\(device.localizedName) \(dims.width)x\(dims.height) \(key) fps"
                choices[name] = CaptureCameraType(name: name, deviceType: device.deviceType, position: device.position, format: format, frameRate: key, dimensions: dims)
            }
        }
        return choices
    }
    
    func setupCameraSelectionMenu() {
        let doit = {(action:UIAction) in
            if let cameras = self.listCameras(), let camera = cameras[action.title] {
                self.chosenCamera = camera
            }
            self.selectCamera()
        }
        
        var options = [UIAction]()
        if let choices = listCameras() {
            for name in choices.keys.sorted() {
                let item = UIAction(title: name, state: .off, handler: doit)
                options.append(item)
            }
            if options.count == 0 {
                let item = UIAction(title: "no camera", state: .off, handler: {_ in })
                options.append(item)
            }
            options[0].state = .on
            chosenCamera = choices[options[0].title]
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
    
    func getCamera() -> AVCaptureDeviceInput? {
        guard let chosenCamera = self.chosenCamera else { return nil }
        guard let device = AVCaptureDevice.default(chosenCamera.deviceType, for: .video, position: chosenCamera.position) else { return nil }
        do {
            try device.lockForConfiguration()
            device.activeFormat = chosenCamera.format
            device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(chosenCamera.frameRate))
            device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(chosenCamera.frameRate))
            device.unlockForConfiguration()
            let videoDeviceInput = try AVCaptureDeviceInput(device: device)
            return videoDeviceInput
        } catch {
            print("Can't create video device input: \(error)")
            return nil
        }
    }
    
    private func selectCamera() {
        self.selectedMovieMode10BitDeviceFormat = nil
        sessionQueue.async {
            guard let videoDeviceInput = self.getCamera() else { return }
            let currentVideoDevice = self.videoDeviceInput.device
            self.session.beginConfiguration()
            self.session.removeInput(self.videoDeviceInput)
            
            if self.session.canAddInput(videoDeviceInput) {
                NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)
                self.session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                self.session.addInput(self.videoDeviceInput)
            }
            if let connection = self.movieFileOutput?.connection(with: .video) {
                self.selectedMovieMode10BitDeviceFormat = self.tenBitVariantOfFormat(activeFormat: self.videoDeviceInput.device.activeFormat)

                // TODO: HDR here?

                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            self.session.commitConfiguration()
        }
    }
}

extension CaptureViewController {
    @objc func rangeSliderValueChanged(_ rangeSlider: RangeSlider) {
        let values = "(\(rangeSlider.lowerBound) \(rangeSlider.thumb) \(rangeSlider.upperBound))"
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
