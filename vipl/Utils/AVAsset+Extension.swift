//
//  AVAsset+Extension.swift
//  vipl
//
//  Created by Steve H. Jung on 1/3/23.
//

import AVFoundation
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

    func info() -> String {
        var info = [String:String]()
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
            let key = String(item.key as! NSString)
            switch key {
            case String(AVMetadataKey.commonKeyCreationDate as NSString), String(AVMetadataKey.quickTimeMetadataKeyCreationDate as NSString):
                info["creation-date"] = String(item.value as! NSString)
            case String(AVMetadataKey.commonKeyDescription as NSString):
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
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [JSONSerialization.WritingOptions.prettyPrinted]),
           let string = String(data: data, encoding: String.Encoding.utf8) {
            return string
        } else {
            return "whatever"
        }
    }
}
