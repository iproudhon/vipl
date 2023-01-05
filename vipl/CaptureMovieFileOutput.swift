//
//  CaptureMovieFileOutput.swift
//  vipl
//
//  Created by Steve H. Jung on 1/2/23.
//

import os
import AVFoundation
import CoreLocation
import UIKit

class CaptureMovieFileOuptut {
    var url: URL?
    var writer: AVAssetWriter?
    var videoWriterInput: AVAssetWriterInput?
    var audioWriterInput: AVAssetWriterInput?
    var depthWriterInput: AVAssetWriterInput?
    var metadataWriterInput: AVAssetWriterInput?
    var metadataAdaptor: AVAssetWriterInputMetadataAdaptor?
    var startTime: CMTime = CMTime.zero
    var latestTime: CMTime = CMTime.zero
    var isRecording: Bool = false

    var recordedDuration: CMTime {
        get {
            if isRecording {
                return self.latestTime - self.startTime
            } else {
                return CMTime.zero
            }
        }
    }

    // TODO: metadata: location & start time
    // AVCaptureVideoOrientation
    func start(url: URL, videoSettings: [String:Any]?, transform: CGAffineTransform, audioSettings: [String:Any]?, location: CLLocation?) throws {
        let writer = try AVAssetWriter(url: url, fileType: .mov)

        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput.expectsMediaDataInRealTime = true
        videoWriterInput.transform = transform
        if writer.canAdd(videoWriterInput) {
            writer.add(videoWriterInput)
        }

        let audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioWriterInput.expectsMediaDataInRealTime = true
        if writer.canAdd(audioWriterInput) {
            writer.add(audioWriterInput)
        }

        var metadata = [AVMutableMetadataItem]()
        var item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = AVMetadataKey.commonKeyMake as NSString
        item.value = UIDevice.current.systemName as NSString
        // TODO: where to get manufacturer name?
        item.value = "Apple" as NSString
        metadata.append(item)

        item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = AVMetadataKey.commonKeyModel as NSString
        item.value = UIDevice.current.model as NSString
        metadata.append(item)

        item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = AVMetadataKey.commonKeySoftware as NSString
        item.value = UIDevice.current.systemVersion as NSString
        metadata.append(item)

        item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = AVMetadataKey.commonKeyCreationDate as NSString
        item.value = Date() as NSDate
        metadata.append(item)

        #if false
        // TODO: to add caption / description / tags
        item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = AVMetadataKey.commonKeyDescription as NSString
        item.identifier = AVMetadataIdentifier.commonIdentifierDescription
        item.value = "hello" as NSString
        metadata.append(item)
        #endif

        if let location = location {
            item = AVMutableMetadataItem()
            item.keySpace = AVMetadataKeySpace.quickTimeMetadata
            item.key = AVMetadataKey.quickTimeMetadataKeyLocationISO6709 as NSString
            item.identifier = AVMetadataIdentifier.quickTimeMetadataLocationISO6709
            item.value = String(format: "%+09.5f%+010.5f%+.0fCRSWGS_84", location.coordinate.latitude, location.coordinate.longitude, location.altitude) as NSString
            metadata.append(item)

            item = AVMutableMetadataItem()
            item.keySpace = AVMetadataKeySpace.quickTimeMetadata
            item.key = AVMetadataKey.quickTimeMetadataKeyLocationISO6709 as NSString
            item.identifier = AVMetadataIdentifier.quickTimeMetadataLocationHorizontalAccuracyInMeters
            item.value = String(format: "%09.6f", location.horizontalAccuracy) as NSString
            metadata.append(item)
        }
        writer.metadata = metadata

        self.writer = writer
        self.videoWriterInput = videoWriterInput
        self.audioWriterInput = audioWriterInput
        self.startTime = CMTime.zero
        self.latestTime = CMTime.zero

        if !writer.startWriting() {
            os_log("failed to start writing: \(writer.error?.localizedDescription ?? "none")")
        }
        self.isRecording = true
    }

    private func nullify() {
        self.url = nil
        self.writer = nil
        self.videoWriterInput = nil
        self.audioWriterInput = nil
        self.depthWriterInput = nil
        self.metadataWriterInput = nil
        self.metadataAdaptor = nil
        self.startTime = CMTime.zero
        self.latestTime = CMTime.zero
        self.isRecording = false
    }

    func stop(completionHandler handler: @escaping () -> Void) {
        guard let writer = self.writer else {
            os_log("stop failed because writing session is not running")
            return
        }
        if writer.status != .writing {
            os_log("not in recording")
            return
        }
        self.isRecording = false
        self.videoWriterInput?.markAsFinished()
        self.audioWriterInput?.markAsFinished()
        self.depthWriterInput?.markAsFinished()
        self.metadataWriterInput?.markAsFinished()
        writer.finishWriting { [weak self] in
            self?.nullify()
            handler()
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer, for mediaType: AVMediaType) {
        if self.writer?.status != .writing {
            return
        }
        self.latestTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if CMTimeCompare(self.startTime, CMTime.zero) == 0 {
            self.writer?.startSession(atSourceTime: self.latestTime)
            self.startTime = self.latestTime
        }
        switch mediaType {
        case .video:
            if self.videoWriterInput?.isReadyForMoreMediaData ?? false {
                self.videoWriterInput?.append(sampleBuffer)
            }
        case .audio:
            if self.audioWriterInput?.isReadyForMoreMediaData ?? false {
                self.audioWriterInput?.append(sampleBuffer)
            }
            break
        case .depthData:
            break
        case .metadata:
            break
        default:
            break
        }
    }
}
