//
//  AVAsset+Extension.swift
//  vipl
//
//  Created by Steve H. Jung on 1/3/23.
//

import AVFoundation
import CoreLocation
import UIKit

extension AVAsset {
    func videoOrientation() -> (orientation: UIDeviceOrientation, device: AVCaptureDevice.Position, transform: CGAffineTransform, reverseTransform: CGAffineTransform) {
        var orientation: UIDeviceOrientation = .unknown
        var device: AVCaptureDevice.Position = .unspecified
        var transform: CGAffineTransform = CGAffineTransformIdentity
        var reverseTransform: CGAffineTransform = CGAffineTransformIdentity

        if let track = self.tracks(withMediaType: .video).first {
            transform = track.preferredTransform
            let t = transform
            if (t.a == 0 && t.b == 1.0 && t.d == 0) {
                orientation = .portrait
                if t.c == 1.0 {
                    device = .front
                    // portraitUpsideDownMirrored
                    reverseTransform = CGAffineTransform(0, -1, -1, 0, track.naturalSize.height, track.naturalSize.width)
                } else if t.c == -1.0 {
                    device = .back
                    // portraitUpsideDown
                    reverseTransform = CGAffineTransform(0, -1, 1, 0, 0, track.naturalSize.width)
                }
            } else if (t.a == 0 && t.b == -1.0 && t.d == 0) {
                orientation = .portraitUpsideDown
                if t.c == -1.0 {
                    device = .front
                    // portraitMirrored
                    reverseTransform = CGAffineTransform(0, 1, 1, 0, 0, 0)
                } else if t.c == 1.0 {
                    // portrait
                    device = .back
                    reverseTransform = CGAffineTransform(0, 1, -1, 0, track.naturalSize.height, 0)
                }
            } else if (t.a == 1.0 && t.b == 0 && t.c == 0) {
                orientation = .landscapeRight
                if t.d == -1.0 {
                    device = .front
                } else if t.d == 1.0 {
                    device = .back
                }
                // reverseTransform = transform
            } else if (t.a == -1.0 && t.b == 0 && t.c == 0) {
                orientation = .landscapeLeft
                if t.d == 1.0 {
                    device = .front
                } else if t.d == -1.0 {
                    device = .back
                    reverseTransform = transform
                }
                // reverseTransform = transform
            }
        }
        return (orientation, device, transform, reverseTransform)
    }

    func info() -> (String?, [String:Any]?) {
        var info = [String:Any]()
        let orientation: UIDeviceOrientation
        (orientation, _, _, _) = self.videoOrientation()
        switch orientation {
        case .portrait:
            info["orientation"] = "portrait"
        case .portraitUpsideDown:
            info["orientation"] = "portrait-upside-down"
        case .landscapeRight:
            info["orientation"] = "landscape"
        case .landscapeLeft:
            info["orientation"] = "landscape-left"
        default:
            info["orientation"] = "unknown"
        }
        info["duration"] = String(format: "%.2f", self.duration.seconds)
        for item in self.metadata {
            let key = String(item.key as? NSString ?? "")
            switch key {
            case String(AVMetadataKey.commonKeyCreationDate as NSString), String(AVMetadataKey.quickTimeMetadataKeyCreationDate as NSString):
                info["creation-date"] = String(item.value as! NSString)
            case String(AVMetadataKey.commonKeyDescription as NSString), String(AVMetadataKey.quickTimeMetadataKeyDescription as NSString):
                info["description"] = String(item.value as! NSString)
            case String(AVMetadataKey.quickTimeMetadataKeyLocationISO6709 as NSString):
                if item.identifier == AVMetadataIdentifier.quickTimeMetadataLocationISO6709 {
                    info["location"] = String(item.value as! NSString)
                } else if item.identifier == AVMetadataIdentifier.quickTimeMetadataLocationHorizontalAccuracyInMeters {
                    info["location.horizontalAccuracy"] = String(item.value as! NSString)
                }
            default:
                break
            }
        }
        var tracksInfo = [String]()
        for track in self.tracks {
            switch track.mediaType {
            case .video:
                info["frame-rate"] = "\(Int(track.nominalFrameRate))"
                info["dimensions"] = "\(Int(track.naturalSize.width))x\(Int(track.naturalSize.height))"
                tracksInfo.append("media-type: video")
            case .audio:
                tracksInfo.append("media-type: audio")
            default:
                tracksInfo.append("media-type: \(track.mediaType) \(track.description)")
            }
        }
        info["tracks"] = tracksInfo

        if let data = try? JSONSerialization.data(withJSONObject: info, options: [JSONSerialization.WritingOptions.prettyPrinted]),
           let string = String(data: data, encoding: String.Encoding.utf8) {
            return (string, info)
        } else {
            return ("whatever", info)
        }
    }

    public static func setDescription(fileURL: URL, description: String, completionHandler: @escaping (Bool) -> Void) {
        // Load the asset
        let asset = AVAsset(url: fileURL)

        // Initialize export session
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            print("Error creating export session")
            completionHandler(false)
            return
        }

        // Fetch existing metadata
        var metadata = asset.metadata

        // Create metadata item for description
        let descriptionMetadataItem = AVMutableMetadataItem()
        descriptionMetadataItem.key = AVMetadataKey.quickTimeMetadataKeyDescription as (NSCopying & NSObjectProtocol)?
        descriptionMetadataItem.keySpace = AVMetadataKeySpace.quickTimeMetadata
        descriptionMetadataItem.value = description as (NSCopying & NSObjectProtocol)?
        descriptionMetadataItem.locale = Locale.current

        // Remove existing description metadata item if it exists
        metadata = metadata.filter { !($0.key as? String == AVMetadataKey.quickTimeMetadataKeyDescription.rawValue && $0.keySpace == .quickTimeMetadata) }

        // Append new description metadata item
        metadata.append(descriptionMetadataItem)

        // Set metadata to export session
        exportSession.metadata = metadata

        // Define output URL
        guard let tmpUrl = FileSystemHelper.getPrimaryTemporaryFileName() else {
            print("cannot get temporary file name")
            completionHandler(false)
            return
        }
        exportSession.outputURL = tmpUrl
        exportSession.outputFileType = AVFileType.mov

        // Start export session
        exportSession.exportAsynchronously(completionHandler: {
            switch exportSession.status {
            case .completed:
                print("Export complete")
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    try FileManager.default.moveItem(at: tmpUrl, to: fileURL)
                    completionHandler(true)
                } catch {
                    print("Failed to move \(tmpUrl) to \(fileURL)")
                }
            case .failed:
                print("Failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
            case .cancelled:
                print("Export cancelled")
            default:
                print("Other Status")
            }
        })
        completionHandler(false)
        return
    }

    static func extractCoordinates(from locationString: String) -> (latitude: Double?, longitude: Double?) {
        let regexPattern = "([+-]?\\d+\\.?\\d*)"

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [])
            let matches = regex.matches(in: locationString, options: [], range: NSRange(location: 0, length: locationString.count))

            if matches.count >= 2 {
                let latitudeRange = matches[0].range
                let longitudeRange = matches[1].range
                let nsString = locationString as NSString

                let latitude = Double(nsString.substring(with: latitudeRange))
                let longitude = Double(nsString.substring(with: longitudeRange))

                return (latitude, longitude)
            }
        } catch {
            print("Regex error: \(error)")
        }

        return (nil, nil)
    }

    static func getLocationName(coordinatesString: String, completionHandler: @escaping (String?) -> Void) {
        let (latitude, longitude) = extractCoordinates(from: coordinatesString)
        guard let latitude = latitude, let longitude = longitude else {
            completionHandler(nil)
            return
        }

        // Initialize a CLLocation with the latitude and longitude
        let location = CLLocation(latitude: latitude, longitude: longitude)

        // Use CLGeocoder to perform reverse geocoding
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { (placemarks, error) in
            if let error = error {
                print("Reverse geocoding failed with error: \(error.localizedDescription)")
                completionHandler(nil)
            } else if let placemark = placemarks?.first {
                // Format the location string from placemark
                let locationName = [placemark.locality, placemark.administrativeArea, placemark.country].compactMap { $0 }.joined(separator: ", ")
                completionHandler(locationName)
            } else {
                completionHandler(nil)
            }
        }
    }
}
