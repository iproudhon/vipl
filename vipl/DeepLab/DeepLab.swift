//
//  DeepLab.swift
//  vipl
//
//  Created by Steve H. Jung on 12/30/22.
//

import AVFoundation
import CoreML
import UIKit

class DeepLab {
    var model: DeepLabV3
    let width: CGFloat = 513
    let height: CGFloat = 513

    let queue = DispatchQueue(label: "deeplabv3.queue")
    var frameImage: CVPixelBuffer? = nil
    var isRunning = false

    init() {
        do {
            let config = MLModelConfiguration()
            model = try DeepLabV3(configuration: config)
        } catch {
            fatalError("Error loading DeepLabV3 mode: \(error.localizedDescription)")
        }
    }

    // darken the background
    func extractMask(outputImage: UIImage, withBlur: Bool) -> UIImage? {
        guard let mask = CIImage(image: outputImage)?.removeWhitePixels() else { return nil}
        if !withBlur {
            return UIImage(ciImage: mask)
        }
        if let blurredMask = mask.applyBlurEffect() {
            return UIImage(ciImage: blurredMask)
        } else {
            return nil
        }
    }

    // extracted segment image
    func extractImage(image: CVPixelBuffer, outputImage: UIImage, withBlur: Bool) -> UIImage? {
        var ciMask = CIImage(image: outputImage)
        if let filter = CIFilter(name: "CIColorInvert") {
            filter.setValue(ciMask, forKey: kCIInputImageKey)
            ciMask = filter.outputImage!
        }
        guard let ciMask = ciMask else { return nil }
        var cgMask = CIContext(options: nil).createCGImage(ciMask, from: ciMask.extent)!
        cgMask = CGImage(maskWidth: cgMask.width,
                         height: cgMask.height,
                         bitsPerComponent: cgMask.bitsPerComponent,
                         bitsPerPixel: cgMask.bitsPerPixel,
                         bytesPerRow: cgMask.bytesPerRow,
                         provider: cgMask.dataProvider!,
                         decode: nil, shouldInterpolate: true)!
        guard let cgImg = CGImage.create(pixelBuffer: image),
              let extractedImage = cgImg.masking(cgMask) else { return nil }
        if !withBlur {
            return UIImage(cgImage: extractedImage)
        }
        if let blurredImage = CIImage(cgImage: extractedImage).applyBlurEffect() {
            return UIImage(ciImage: blurredImage)
        } else {
            return nil
        }
    }

    func uiImageSetAlpha(uiImage: UIImage, alpha: CGFloat) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(uiImage.size, false, uiImage.scale)
        uiImage.draw(at: CGPoint.zero, blendMode: .normal, alpha: alpha)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
    }


    func runInner(targetView: OverlayView, rotate: Bool, time: CMTime, freeze: Bool) {
        self.isRunning = true
        objc_sync_enter(self)
        let image = self.frameImage
        objc_sync_exit(self)
        defer { self.isRunning = false }

        guard let image = image,
              let rotatedImage = !rotate ? image: rotate90PixelBuffer(image, factor: 3),
              let resizedImage = resizePixelBuffer(rotatedImage, width: Int(self.width), height: Int(self.height)),
              let prediction = try? self.model.prediction(image: resizedImage),
              let outputImage = prediction.semanticPredictions.image(min: 0, max: 1, axes: (0, 0, 1)) else {
            return
        }

        if false {
            // alpha mask to block out background
            let alphaMask = extractMask(outputImage: outputImage, withBlur: true)?.resized(to: CGSize(width: image.size.height, height: image.size.width))
            DispatchQueue.main.async {
                targetView.image = alphaMask
            }
        } else {
            // extract segment itself
            let extractedImage = extractImage(image: rotatedImage, outputImage: outputImage, withBlur: false)?.resized(to: CGSize(width: image.size.height, height: image.size.width))
            let extractedImageWithAlpha = uiImageSetAlpha(uiImage: extractedImage!, alpha: 0.6)
            DispatchQueue.main.async {
                if !freeze {
                    targetView.setSnap(extractedImageWithAlpha, time)
                } else {
                    targetView.pushPose(pose: nil, snap: extractedImageWithAlpha, time: time)
                }
                targetView.draw(size: extractedImageWithAlpha.size)
            }
        }

        objc_sync_enter(self)
        let more = self.frameImage != nil && image != self.frameImage
        if !more {
            self.frameImage = nil
        }
        objc_sync_exit(self)
        if more {
            self.runInner(targetView: targetView, rotate: rotate, time: time, freeze: freeze)
        }
    }

    func runModel(targetView: OverlayView, image: CVPixelBuffer, rotate: Bool, time: CMTime, freeze: Bool = false) {
        objc_sync_enter(self)
        self.frameImage = image
        objc_sync_exit(self)
        guard !isRunning else { return }

        queue.async {
            self.runInner(targetView: targetView, rotate: rotate, time: time, freeze: freeze)
        }
    }
}
