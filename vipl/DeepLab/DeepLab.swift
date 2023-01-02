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
    func extractMask(mask: UIImage, withBlur: Bool) -> UIImage? {
        guard let mask = CIImage(image: mask)?.removeWhitePixels() else { return nil}
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
    func extractImage(image: CVPixelBuffer, mask: UIImage, withBlur: Bool) -> UIImage? {
        var ciMask = CIImage(image: mask)
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

    // white: through, black: masking
    func segmentsToMask(segments: MLMultiArray) -> CGImage? {
        let width = segments.shape[0].intValue, height = segments.shape[1].intValue
        var ptr = [UInt32](UnsafeMutableBufferPointer(start: UnsafeMutablePointer<UInt32>(OpaquePointer(segments.dataPointer)), count: width * height))
        // regardless of type of object found
        var pixels: [UInt32] = ptr.map({ UInt32($0 > 0 ? 0xFFFFFFFF : (UInt32(255) << 24)) })

        let cgImage = pixels.withUnsafeMutableBytes { (ptr) -> CGImage in
          let ctx = CGContext(
            data: ptr.baseAddress,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: MemoryLayout<UInt32>.size * Int(width),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
              + CGImageAlphaInfo.premultipliedFirst.rawValue
          )!
          return ctx.makeImage()!
        }
        return cgImage
    }

    func runInner(assetId: String, targetView: OverlayView, rotate: Bool, time: CMTime, freeze: Bool) {
        self.isRunning = true
        objc_sync_enter(self)
        let image = self.frameImage
        objc_sync_exit(self)
        defer { self.isRunning = false }

        let id = "\(assetId):mask:\(Int(time.seconds * 100))"
        guard let image = image,
              let rotatedImage = !rotate ? image: rotate90PixelBuffer(image, factor: 3),
              let resizedImage = resizePixelBuffer(rotatedImage, width: Int(self.width), height: Int(self.height)) else {
            return
        }
        let cgMask: CGImage
        if let cached = Cache.Default.get(id) {
            cgMask = cached as! CGImage
        } else {
            guard let prediction = try? self.model.prediction(image: resizedImage),
                  let mask = segmentsToMask(segments: prediction.semanticPredictions) else {
                return
            }
            cgMask = mask
            Cache.Default.set(id, cgMask)
        }
        let mask = UIImage(cgImage: cgMask)

        if false {
            // alpha mask to block out background
            let alphaMask = extractMask(mask: mask, withBlur: true)?.resized(to: CGSize(width: image.size.height, height: image.size.width))
            DispatchQueue.main.async {
                targetView.image = alphaMask
            }
        } else {
            // extract segment itself
            let extractedImage = extractImage(image: rotatedImage, mask: mask, withBlur: false)?.resized(to: CGSize(width: image.size.height, height: image.size.width))
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
            self.runInner(assetId: assetId, targetView: targetView, rotate: rotate, time: time, freeze: freeze)
        }
    }

    func runModel(assetId: String, targetView: OverlayView, image: CVPixelBuffer, rotate: Bool, time: CMTime, freeze: Bool = false) {
        objc_sync_enter(self)
        self.frameImage = image
        objc_sync_exit(self)
        guard !isRunning else { return }

        queue.async {
            self.runInner(assetId: assetId, targetView: targetView, rotate: rotate, time: time, freeze: freeze)
        }
    }
}
