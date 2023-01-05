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
}
