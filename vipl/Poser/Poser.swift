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

    class Task {
        var assetId: String?
        var pixelBuffer: CVPixelBuffer?
        var transform: CGAffineTransform?
        var time: CMTime?
        var freeze: Bool?
        var completionHandler: ((Task?, Person?) -> Void)?
    }
    var task: Task?

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

    func runInner() {
        objc_sync_enter(self)
        guard let estimator = poseEstimator,
              let task = self.task,
              let pixelBuffer = task.pixelBuffer,
              let time = task.time else {
            self.task = nil
            objc_sync_exit(self)
            return
        }
        self.task = nil
        objc_sync_exit(self)
        defer { self.isRunning = false }

        let result: Person
        let id = "\(task.assetId ?? ""):pose:\(Int64(time.seconds * 1000))"
        if task.assetId != nil, let cached = Cache.Default.get(id) {
            result = cached as! Person
        } else {
            guard let (uncached, _) = try? estimator.estimateSinglePose(on: pixelBuffer) else {
                os_log("Error running pose estimation.", type: .error)
                return
            }
            result = uncached
            if task.assetId != nil {
                Cache.Default.set(id, result)
            }
        }

        task.completionHandler?(task, result)

        objc_sync_enter(self)
        let more = self.task != nil
        objc_sync_exit(self)
        if more {
            runInner()
        }
    }

    func runModel(assetId: String?, targetView: OverlayView, pixelBuffer: CVPixelBuffer, transform: CGAffineTransform, time: CMTime, freeze: Bool = false, completionHandler: @escaping (Person?) -> Void) {
        let task = Task()
        task.assetId = assetId
        task.transform = transform
        task.pixelBuffer = transform == CGAffineTransformIdentity ? pixelBuffer : pixelBuffer.transformed(transform: transform)
        task.time = time
        task.freeze = freeze
        task.completionHandler = { task, result in
            guard let task = task,
                  let result = result else {
                return
            }
            var valid = result.score >= self.minimumScore
            for kp in result.keyPoints {
                if !valid {
                    break
                }
                switch kp.bodyPart {
                case .leftAnkle, .leftKnee, .leftHip, .rightAnkle, .rightKnee, .rightHip:
                    if kp.score < self.minimumScore {
                        valid = false
                    }
                default:
                    break
                }
            }

            if !task.freeze! {
                targetView.setPose(valid ? result : nil, task.time!)
            } else {
                if valid {
                    targetView.pushPose(pose: result, snap: nil, time: task.time!)
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
                targetView.draw(size: task.pixelBuffer!.size)
            }
            if valid {
                completionHandler(result)
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

enum PoserConstants {
  static let defaultThreadCount = 4
  static let defaultDelegate: Delegates = .gpu
  static let defaultModelType: ModelType = .movenetThunder

  static let minimumScore: Float32 = 0.3
}
