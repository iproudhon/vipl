//
//  CaptureHelper.swift
//  vipl
//
//  Created by Steve H. Jung on 12/23/22.
//

import AVFoundation
import AVKit
import MobileCoreServices
import CoreLocation

class CaptureCameraType {
    var name: String
    var deviceType: AVCaptureDevice.DeviceType
    var position: AVCaptureDevice.Position
    var format: AVCaptureDevice.Format
    var frameRate: Float64
    var dimensions: CMVideoDimensions
    var depthDataFormat: AVCaptureDevice.Format?

    init(name: String, deviceType: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position, format: AVCaptureDevice.Format, frameRate: Float64, dimensions: CMVideoDimensions, depthDataFormat: AVCaptureDevice.Format?) {
        self.name = name
        self.deviceType = deviceType
        self.position = position
        self.format = format
        self.frameRate = frameRate
        self.dimensions = dimensions
        self.depthDataFormat = depthDataFormat
    }
}

class CaptureHelper {
    // max dimension: 320, 640, 1280, 1920
    static let maxDepthWidth = 640

    static func listCameras() -> [String:CaptureCameraType]? {
        var session: AVCaptureDevice.DiscoverySession?
        if #available(iOS 15.4, *) {
            session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .builtInTrueDepthCamera, .builtInLiDARDepthCamera], mediaType: .video, position: .unspecified)
        } else {
            session = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified)
        }

        func getDepthDimensionsAndRate(format: AVCaptureDevice.Format) -> (AVCaptureDevice.Format, CMVideoDimensions, Float64) {
            var depthFormat = format
            var depthDims = CMVideoDimensions(width: 0, height: 0), depthRate: Float64 = 0
            for i in format.supportedDepthDataFormats.filter({ depthFormat in
                return CMFormatDescriptionGetMediaSubType(depthFormat.formatDescription) == kCVPixelFormatType_DepthFloat32
            }) {
                let dims = i.formatDescription.dimensions
                for range in i.videoSupportedFrameRateRanges {
                    if dims.width >= depthDims.width && range.maxFrameRate >= depthRate {
                        depthFormat = i
                        depthDims = dims
                        depthRate = range.maxFrameRate
                    }
                }
            }
            return (depthFormat, depthDims, depthRate)
        }

        var choices: [String:CaptureCameraType] = [:]
        guard let session = session else { return nil }
        for device in session.devices {
            // frameRate -> format
            var rate2format: [Float64:AVCaptureDevice.Format] = [:]
            var rate2depthFormat: [Float64:AVCaptureDevice.Format] = [:]
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

                if dims.width > maxDepthWidth {
                    continue
                }
                let (_, depthDims, depthRate) = getDepthDimensionsAndRate(format: format)
                if depthDims.width > 0 && depthRate > 0 {
                    rate2depthFormat[depthRate] = format
                }
            }

            for key in rate2format.keys.sorted() {
                guard let format = rate2format[key] as AVCaptureDevice.Format? else { continue }
                let dims = format.formatDescription.dimensions
                let name = "\(device.localizedName) \(dims.width)x\(dims.height) \(key) fps"
                choices[name] = CaptureCameraType(name: name, deviceType: device.deviceType, position: device.position, format: format, frameRate: key, dimensions: dims, depthDataFormat: nil)
            }
            for key in rate2depthFormat.keys.sorted() {
                guard let format = rate2depthFormat[key] as AVCaptureDevice.Format? else { continue }
                let dims = format.formatDescription.dimensions
                let name = "\(device.localizedName) Depthx\(dims.width)x\(dims.height) \(key) fps"
                let (depthFormat, _, _) = getDepthDimensionsAndRate(format: format)
                choices[name] = CaptureCameraType(name: name, deviceType: device.deviceType, position: device.position, format: format, frameRate: key, dimensions: dims, depthDataFormat: depthFormat)
            }
        }
        return choices
    }

    static func getCaptureDeviceInput(cam: CaptureCameraType) throws -> AVCaptureDeviceInput! {
        guard let device = AVCaptureDevice.default(cam.deviceType, for: .video, position: cam.position) else {
            throw NSError(domain: "user", code: 0, userInfo: ["message": "device type not found"])
        }
        try device.lockForConfiguration()
        device.activeFormat = cam.format
        device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(cam.frameRate))
        device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(cam.frameRate))
        device.unlockForConfiguration()
        let videoDeviceInput = try AVCaptureDeviceInput(device: device)
        return videoDeviceInput
    }

    // double buffering

    static func trimVideo(url: URL, start: Double, end: Double, to: String?) -> Bool {
        let movie = AVAsset(url: url)
        let range = CMTimeRangeFromTimeToTime(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        return true
    }

    // TODO: handle multiple tracks? .meta, etc., attributes?
    static func mergeVideos(_ fn1: URL?, _ fn2: URL, _ out: URL, maxSeconds: Double) -> Bool {
        let movie2 = AVAsset(url: fn2)
        if fn1 == nil || movie2.duration.seconds >= maxSeconds {
            do {
                try FileManager.default.moveItem(at: fn2, to: out)
                return true
            } catch {
                print("Failed to move \(fn2) -> \(out): \(error.localizedDescription)")
                return false
            }
        }

        let movie1 = AVAsset(url: fn1!)
        let movie1start = movie1.duration.seconds - (maxSeconds - movie2.duration.seconds)
        let movie1range = CMTimeRangeMake(start: CMTime(seconds: movie1start, preferredTimescale: 600), duration: CMTime(seconds: movie1.duration.seconds - movie1start, preferredTimescale: 600))
        let movie2range = CMTimeRangeMake(start: movie1range.duration, duration: movie2.duration)

        let movie = AVMutableComposition()
        let videoTrack = movie.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = movie.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        let movie2start = CMTime(seconds: movie1range.duration.seconds, preferredTimescale: 600)
        try? videoTrack?.insertTimeRange(movie1range, of: movie1.tracks(withMediaType: .video).first!, at: movie2start)
        try? audioTrack?.insertTimeRange(movie1range, of: movie1.tracks(withMediaType: .audio).first!, at: movie2start)

        let exporter = AVAssetExportSession(asset: movie, presetName: AVAssetExportPresetHEVCHighestQuality)
        exporter?.outputURL = out
        exporter?.outputFileType = .mov
        exporter?.exportAsynchronously(completionHandler: { [weak exporter] in
            DispatchQueue.main.async {
                if let error = exporter?.error { //3
                    print("Failed to merge \(fn1!.path) and \(fn2.path): \(error.localizedDescription)")
                } else {
                    try? FileManager.default.removeItem(at: fn1!)
                    try? FileManager.default.removeItem(at: fn2)
                    print("Merged \(fn1!.path) and \(fn2.path) to \(out.path)")
                }
            }
        })

        return true
    }

    static func appendMovie(to: URL, it: URL) -> Bool {
        if !FileManager.default.fileExists(atPath: it.path) {
            print("\(it.path) not found")
            return false
        }
        if !FileManager.default.fileExists(atPath: to.path) {
            try? FileManager.default.moveItem(atPath: it.path, toPath: to.path)
            return true
        }

        let movie1 = AVAsset(url: to)
        let movie2 = AVAsset(url: it)
        let movie1range = CMTimeRangeMake(start: CMTime.zero, duration: movie1.duration)
        let movie2range = CMTimeRangeMake(start: CMTime.zero, duration: movie2.duration)
        let movie2start = CMTime(seconds: movie1.duration.seconds, preferredTimescale: 600)
        let movie1track = movie1.tracks(withMediaType: .video).first!
        let movie2track = movie2.tracks(withMediaType: .video).first!

        var movie1size = CGSizeApplyAffineTransform(movie1track.naturalSize, movie1track.preferredTransform)
        var movie2size = CGSizeApplyAffineTransform(movie1track.naturalSize, movie2track.preferredTransform)
        movie1size.width = abs(movie1size.width)
        movie2size.width = abs(movie2size.width)
        if movie1size != movie2size {
            print("sizes don't match: \(movie1size) <> \(movie2size)")
            return false
        }

        let transformInstruction = AVMutableVideoCompositionInstruction()
        transformInstruction.timeRange = CMTimeRangeMake(start: .zero, duration: CMTimeAdd(movie1.duration, movie2.duration))
        let movie1instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: movie1track)
        movie1instruction.setTransform(movie1track.preferredTransform, at: .zero)
        let movie2instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: movie2track)
        movie1instruction.setTransform(movie2track.preferredTransform, at: .zero)
        transformInstruction.layerInstructions = [movie1instruction, movie2instruction]

        let mainComposition = AVMutableVideoComposition()
        mainComposition.instructions = [transformInstruction]
        mainComposition.frameDuration = movie1track.minFrameDuration
        mainComposition.renderSize = movie1size

        let movie = AVMutableComposition()
        let videoTrack = movie.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioTrack = movie.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

        try? videoTrack?.insertTimeRange(movie1range, of: movie1.tracks(withMediaType: .video).first!, at: CMTime.zero)
        try? videoTrack?.insertTimeRange(movie2range, of: movie2.tracks(withMediaType: .video).first!, at: movie2start)
        try? audioTrack?.insertTimeRange(movie1range, of: movie1.tracks(withMediaType: .audio).first!, at: CMTime.zero)
        try? audioTrack?.insertTimeRange(movie2range, of: movie2.tracks(withMediaType: .audio).first!, at: movie2start)

        let tmpUrl = URL(fileURLWithPath: (NSTemporaryDirectory() as NSString).appendingPathComponent((NSUUID().uuidString as NSString).appendingPathExtension("mov")!))
        let exporter = AVAssetExportSession(asset: movie, presetName:   AVAssetExportPresetHEVCHighestQuality)
        exporter?.outputURL = tmpUrl
        exporter?.outputFileType = .mov
        exporter?.metadata = movie1.metadata
        exporter?.videoComposition = mainComposition
        exporter?.exportAsynchronously(completionHandler: { [weak exporter] in
            DispatchQueue.main.async {
                if let error = exporter?.error { //3
                    print("Failed to append \(it.path) and \(to.path): \(error.localizedDescription)")
                } else {
                    if FileManager.default.fileExists(atPath: tmpUrl.path) {
                        try? FileManager.default.removeItem(at: to)
                        try? FileManager.default.removeItem(at: it)
                        try? FileManager.default.moveItem(at: tmpUrl, to: to)
                    } else {
                        try? FileManager.default.removeItem(at: to)
                        try? FileManager.default.moveItem(at: it, to: to)
                    }
                    print("Appended \(it.path) to \(to.path)")
                }
            }
        })
        return true
    }
}

extension CaptureHelper {
    func addMetadata(asset: AVAsset, metadata: [AVMetadataItem]) -> Bool {
        return false
    }
}
