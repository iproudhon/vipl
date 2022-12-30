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

    private var poseEstimator: PoseEstimator?

    let queue = DispatchQueue(label: "poser.queue")

    var isRunning = false

    func updateModel() {
        queue.async {
            do {
                switch self.modelType {
                case .posenet:
                    self.poseEstimator = try PoseNet(
                        threadCount: self.threadCount,
                        delegate: self.delegate)
                case .movenetLighting, .movenetThunder:
                    self.poseEstimator = try MoveNet(
                        threadCount: self.threadCount,
                        delegate: self.delegate,
                        modelType: self.modelType)
                }
            } catch let error {
                os_log("Error: %@", log: .default, type: .error, String(describing: error))
            }
        }
    }

    func runModel(targetView: OverlayView, pixelBuffer: CVPixelBuffer, transform: CGAffineTransform) {
        guard !isRunning else { return }
        guard let estimator = poseEstimator else { return }

        queue.async {
            self.isRunning = true
            defer { self.isRunning = false }

            do {
                let (result, times) = try estimator.estimateSinglePose(on: pixelBuffer)

                DispatchQueue.main.async {
                    // self.totalTimeLabel.text = String(format: "%.2fms", times.total * 1000)
                    // self.scoreLabel.text = String(format: "%.3f", result.score)
                    // print("Poser: \(String(format: "%.3f", result.score))  \(String(format: "%.2fms", times.total * 1000))")

                    //let image = UIImage(ciImage: CIImage(cvPixelBuffer: pixelBuffer))
                    // let rect = CGRectMake(0, 0, size.width, size.height)
                    UIGraphicsBeginImageContextWithOptions(pixelBuffer.size, false, 1.0)
                    let image = UIGraphicsGetImageFromCurrentImageContext()!
                    UIGraphicsEndImageContext()

                    // If score is too low, clear result remaining in the overlayView.
                    if result.score < self.minimumScore {
                        targetView.image = nil
                        return
                    }

                    // Visualize the pose estimation result.
                    targetView.image = nil
                    targetView.draw(at: image, person: result, transform: transform)
                }
            } catch {
                os_log("Error running pose estimation.", type: .error)
                return
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
