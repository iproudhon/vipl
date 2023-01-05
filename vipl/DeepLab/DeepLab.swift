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
    static var model: DeepLabV3?
    let width: CGFloat = 513
    let height: CGFloat = 513

    let queue = DispatchQueue(label: "deeplabv3.queue")
    var isRunning: Bool = false

    class Task {
        var assetId: String?
        var pixelBuffer: CVPixelBuffer?
        var transform: CGAffineTransform?
        var time: CMTime?
        var freeze: Bool?
        var completionHandler: ((Task?, UIImage?) -> Void)?
    }
    var task: Task?

    // TODO: make it thread-safe
    init() {
        if DeepLab.model == nil {
            do {
                let config = MLModelConfiguration()
                DeepLab.model = try DeepLabV3(configuration: config)
            } catch {
                fatalError("Error loading DeepLabV3 mode: \(error.localizedDescription)")
            }
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
        let ptr = [UInt32](UnsafeMutableBufferPointer(start: UnsafeMutablePointer<UInt32>(OpaquePointer(segments.dataPointer)), count: width * height))
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

    func transformPixelBuffer(pixelBuffer: CVPixelBuffer, transform: CGAffineTransform) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).transformed(by: transform)
        var outPixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(ciImage.extent.width),
                                         Int(ciImage.extent.height),
                                         CVPixelBufferGetPixelFormatType(pixelBuffer),
                                         nil,
                                         &outPixelBuffer)
        guard (status == kCVReturnSuccess) else {
            return nil
        }
        let ctx = CIContext(options: nil)
        ctx.render(ciImage, to: outPixelBuffer!)
        return outPixelBuffer
    }

    func transformUIImage(image: UIImage, transform: CGAffineTransform) -> UIImage? {
        var ciImage = image.ciImage
        if ciImage == nil {
            ciImage = CIImage(cgImage: image.cgImage!)
        }
        ciImage?.transformed(by: transform)
        return UIImage(ciImage: ciImage!)
    }

    func runInner() {
        objc_sync_enter(self)
        guard let task = self.task,
              let pixelBuffer = task.pixelBuffer,
              let time = task.time else {
            self.task = nil
            objc_sync_exit(self)
            return
        }
        self.task = nil
        objc_sync_exit(self)
        defer { self.isRunning = false }

        let id = "\(task.assetId ?? ""):mask:\(Int(time.seconds * 100))"
        guard let resizedImage = pixelBuffer.resized(to: CGSize(width: self.width, height: self.height)) else { return }

        let cgMask: CGImage
        if task.assetId != nil, let cached = Cache.Default.get(id) {
            cgMask = cached as! CGImage
        } else {
            guard let model = DeepLab.model,
                  let prediction = try? model.prediction(image: resizedImage),
                  let mask = segmentsToMask(segments: prediction.semanticPredictions) else {
                return
            }
            cgMask = mask
            if task.assetId != nil {
                Cache.Default.set(id, cgMask)
            }
        }
        let mask = UIImage(cgImage: cgMask)

        if false {
            // alpha mask to block out background
            let alphaMask = extractMask(mask: mask, withBlur: true)?.resized(to: CGSize(width: pixelBuffer.size.height, height: pixelBuffer.size.width))
            task.completionHandler?(task, alphaMask)
        } else {
            // extract segment itself
            let resizedMask = mask.resized(to: pixelBuffer.size)
            let extractedImage = extractImage(image: pixelBuffer, mask: resizedMask, withBlur: false)
            let extractedImageWithAlpha = uiImageSetAlpha(uiImage: extractedImage!, alpha: 0.6)

            task.completionHandler?(task, extractedImageWithAlpha)
        }

        objc_sync_enter(self)
        let more = self.task != nil
        objc_sync_exit(self)
        if more {
            runInner()
        }
    }

    func runModel(assetId: String, targetView: OverlayView, image: CVPixelBuffer, transform: CGAffineTransform, time: CMTime, freeze: Bool = false) {
        let task = Task()
        task.assetId = assetId
        task.transform = transform
        task.pixelBuffer = transform == CGAffineTransformIdentity ? image : transformPixelBuffer(pixelBuffer: image, transform: transform)
        task.time = time
        task.freeze = freeze
        task.completionHandler = { (task, image) in
            guard let task = task,
                  let image = image,
                  let transform = task.transform,
                  let revertedImage = transform == CGAffineTransformIdentity ? image : self.transformUIImage(image: image, transform: transform.inverted()) else {
                return
            }

            DispatchQueue.main.async {
                if !(task.freeze ?? true) {
                    targetView.setSnap(revertedImage, task.time!)
                } else {
                    targetView.pushPose(pose: nil, snap: revertedImage, time: task.time!)
                }
                targetView.draw(size: revertedImage.size)
            }
        }

        objc_sync_enter(self)
        self.task = task
        if isRunning {
            objc_sync_exit(self)
            return
        }
        isRunning = true
        objc_sync_exit(self)

        queue.async {
            self.runInner()
        }
    }
}
