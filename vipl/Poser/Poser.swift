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
        var completionHandler: ((Task?, Golfer?) -> Void)?
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

    func estimate(on: CVPixelBuffer) throws -> (Golfer?, Times?) {
        guard let estimator = poseEstimator else { return (nil, nil) }
        let (person, times) = try estimator.estimateSinglePose(on: on)
        return (Golfer(person), times)
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

        let result: Golfer
        let id = "\(task.assetId ?? ""):pose:\(Int64(time.seconds * 1000))"
        if task.assetId != nil, let cached = Cache.Default.get(id) {
            result = cached as! Golfer
        } else {
            guard let (uncached, _) = try? estimate(on: pixelBuffer),
                  let uncached = uncached else {
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

    func isValidPose(_ g: Golfer) -> Bool {
        // overal score and key parts' score should be above minimum
        if g.score < minimumScore ||
            g.leftHip.score < minimumScore ||
            g.rightHip.score < minimumScore ||
            g.leftKnee.score < minimumScore ||
            g.rightKnee.score < minimumScore ||
            (g.leftAnkle.score < minimumScore && g.rightAnkle.score < minimumScore) {
            return false
        }

        func isBelow(_ a: GolferBodyPoint, _ b: GolferBodyPoint) -> Bool {
            return a.score >= minimumScore && b.score >= minimumScore && a.orgPt.y > b.orgPt.y
        }

        // sholders shoulbe above knees, knees above ankles
        if isBelow(g.rightShoulder, g.rightKnee) ||
            isBelow(g.rightShoulder, g.leftKnee) ||
            isBelow(g.leftShoulder, g.rightKnee) ||
            isBelow(g.leftShoulder, g.leftKnee) ||
            isBelow(g.rightKnee, g.rightAnkle) ||
            isBelow(g.rightKnee, g.leftAnkle) ||
            isBelow(g.leftKnee, g.rightAnkle) ||
            isBelow(g.leftKnee, g.leftAnkle) {
            return false
        }

        // wrist should be together
        if g.leftWrist.score >= minimumScore && g.rightWrist.score >= minimumScore && g.leftWrist.orgPt.distance(to: g.rightWrist.orgPt) > g.unit / 3.0 {
            return false
        }

        return true
    }

    func runModel(assetId: String?, targetView: OverlayView, pixelBuffer: CVPixelBuffer, transform: CGAffineTransform, time: CMTime, freeze: Bool = false, completionHandler: @escaping (Golfer?) -> Void) {
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
            let valid = self.isValidPose(result)

            if !task.freeze! {
                targetView.setPose(valid ? result : nil, task.time!)
            } else {
                if valid {
                    targetView.pushPose(pose: result, snap: nil, time: task.time!)
                }
            }
            if let log = self.logFunc {
                log("%%%: " + String(format: "%.1f leftAnkle=%.1f rightAnkle=%.1f leftKnee=%.1f rightKnee=%.1f leftHip=%.1f rightHip=%.1f", result.score, result.leftAnkle.score, result.rightAnkle.score, result.leftKnee.score, result.rightKnee.score, result.leftHip.score, result.rightHip.score))
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
