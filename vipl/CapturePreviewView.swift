//
//  CapturePreviewView.swift
//  vipl
//
//  Created by Steve H. Jung on 12/14/22.
//

import UIKit
import AVFoundation

class CapturePreviewView: UIView {
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
        }
        // TODO: compare .resizeAspect & .resizeAspectFill
        layer.videoGravity = .resizeAspect
        return layer
    }
    
    var session: AVCaptureSession? {
        get {
            return videoPreviewLayer.session
        }
        set {
            videoPreviewLayer.session = newValue
        }
    }
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
}
