//
//  Poser.swift
//  vipl
//
//  Created by Steve H. Jung on 12/29/22.
//

import AVFoundation
import UIKit
import os

class Poser {
    private var modelType: ModelType = PoserConstants.defaultModelType
    private var threadCount: Int = PoserConstants.defaultThreadCount
    private var delegate: Delegates = PoserConstants.defaultDelegate
    private let minimumScore = PoserConstants.minimumScore

    static var movenetThunder: MoveNet?
    static var movenetLightning: MoveNet?

    private var poseEstimator: PoseEstimator?
    var logFunc: ((_ msg: String) -> Void)?

    let queue = DispatchQueue(label: "poser.queue")

    var isRunning = false

    func updateModel(modelType: ModelType = .movenetThunder) {
        queue.async {
            self.modelType = modelType
            do {
                switch self.modelType {
                case .posenet:
                    self.poseEstimator = try PoseNetTF(
                        threadCount: self.threadCount,
                        delegate: self.delegate)
                case .movenetLighting:
                    if Poser.movenetLightning == nil {
                        Poser.movenetLightning = try MoveNet(threadCount: self.threadCount, delegate: self.delegate, modelType: self.modelType)
                    }
                    self.poseEstimator = Poser.movenetLightning
                case .movenetThunder:
                    if Poser.movenetThunder == nil {
                        Poser.movenetThunder = try MoveNet(threadCount: self.threadCount, delegate: self.delegate, modelType: self.modelType)
                    }
                    self.poseEstimator = Poser.movenetThunder
                }
            } catch let error {
                os_log("Error: %@", log: .default, type: .error, String(describing: error))
            }
        }
    }

    func rotatePixelBuffer(pixelBuffer: CVPixelBuffer, transform: CGAffineTransform) -> CVPixelBuffer? {
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

    func runModel(assetId: String?, targetView: OverlayView, pixelBuffer: CVPixelBuffer, transform: CGAffineTransform, time: CMTime, freeze: Bool = false) {
        objc_sync_enter(self)
        if isRunning {
            objc_sync_exit(self)
            return
        }
        isRunning = true
        objc_sync_exit(self)

        guard let estimator = poseEstimator,
              let outPixelBuffer = transform == CGAffineTransformIdentity ? pixelBuffer : rotatePixelBuffer(pixelBuffer: pixelBuffer, transform: transform) else {
            isRunning = false
            return
        }
        queue.async {
            defer { self.isRunning = false }

            let result: Person
            let id = "\(assetId ?? ""):pose:\(Int(time.seconds * 100))"
            if assetId != nil, let cached = Cache.Default.get(id) {
                result = cached as! Person
            } else {
                guard let (uncached, _) = try? estimator.estimateSinglePose(on: outPixelBuffer) else {
                    os_log("Error running pose estimation.", type: .error)
                    return
                }
                result = uncached
                if assetId != nil {
                    Cache.Default.set(id, result)
                }
            }
            if !freeze {
                targetView.setPose(result.score < self.minimumScore ? nil : result, time)
            } else {
                if result.score >= self.minimumScore {
                    targetView.pushPose(pose: result, snap: nil, time: time)
                }
            }
            if let log = self.logFunc {
                var msg = String(format: "%.1f ", result.score)
                for p in result.keyPoints {
                    msg += "\(p.bodyPart):" + String(format: "%.1f", p.score) + " "
                }
                log("%%%: " + msg)
            }
            DispatchQueue.main.async {
                targetView.draw(size: outPixelBuffer.size)
            }
        }
    }
}

enum PoserConstants {
  static let defaultThreadCount = 4
  static let defaultDelegate: Delegates = .gpu
  static let defaultModelType: ModelType = .movenetThunder

  static let minimumScore: Float32 = 0.2
}
