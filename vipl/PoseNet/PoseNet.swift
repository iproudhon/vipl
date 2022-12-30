/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation details of a facade to interact with the PoseNet model, includes input
 preprocessing and calling the model's prediction function.
*/

import CoreML
import Vision
import UIKit

protocol PoseNetDelegate: AnyObject {
    func poseNet(_ poseNet: PoseNet, didPredict predictions: PoseNetOutput)
}

class PoseNet {
    /// The delegate to receive the PoseNet model's outputs.
    weak var delegate: PoseNetDelegate?

    /// The PoseNet model's input size.
    ///
    /// All PoseNet models available from the Model Gallery support the input sizes 257x257, 353x353, and 513x513.
    /// Larger images typically offer higher accuracy but are more computationally expensive. The ideal size depends
    /// on the context of use and target devices, typically discovered through trial and error.
    let modelInputSize = CGSize(width: 513, height: 513)

    /// The PoseNet model's output stride.
    ///
    /// Valid strides are 16 and 8 and define the resolution of the grid output by the model. Smaller strides
    /// result in higher-resolution grids with an expected increase in accuracy but require more computation. Larger
    /// strides provide a more coarse grid and typically less accurate but are computationally cheaper in comparison.
    ///
    /// - Note: The output stride is dependent on the chosen model and specified in the metadata. Other variants of the
    /// PoseNet models are available from the Model Gallery.
    let outputStride = 16

    /// The Core ML model that the PoseNet model uses to generate estimates for the poses.
    ///
    /// - Note: Other variants of the PoseNet model are available from the Model Gallery.
    private let poseNetMLModel: MLModel

    // TODO: added by me
    var poseBuilderConfiguration = PoseBuilderConfiguration()
    let queue = DispatchQueue(label: "posenet.queue")
    var isRunning = false

    init() throws {
        poseNetMLModel = try PoseNetMobileNet075S16FP16(configuration: .init()).model
        //poseNetMLModel = try PoseNetMobileNet100S16FP16(configuration: .init()).model
    }

    /// Calls the `prediction` method of the PoseNet model and returns the outputs to the assigned
    /// `delegate`.
    ///
    /// - parameters:
    ///     - image: Image passed by the PoseNet model.
    func predict(_ image: CGImage) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Wrap the image in an instance of PoseNetInput to have it resized
            // before being passed to the PoseNet model.
            let input = PoseNetInput(image: image, size: self.modelInputSize)

            guard let prediction = try? self.poseNetMLModel.prediction(from: input) else {
                return
            }

            let poseNetOutput = PoseNetOutput(prediction: prediction,
                                              modelInputSize: self.modelInputSize,
                                              modelOutputStride: self.outputStride)

            DispatchQueue.main.async {
                self.delegate?.poseNet(self, didPredict: poseNetOutput)
            }
        }
    }

    // TODO: added
    struct JointSegment {
        let jointA: Joint.Name
        let jointB: Joint.Name
    }

    static let jointSegments = [
        JointSegment(jointA: .leftHip, jointB: .leftShoulder),
        JointSegment(jointA: .leftShoulder, jointB: .leftElbow),
        JointSegment(jointA: .leftElbow, jointB: .leftWrist),
        JointSegment(jointA: .leftHip, jointB: .leftKnee),
        JointSegment(jointA: .leftKnee, jointB: .leftAnkle),
        JointSegment(jointA: .rightHip, jointB: .rightShoulder),
        JointSegment(jointA: .rightShoulder, jointB: .rightElbow),
        JointSegment(jointA: .rightElbow, jointB: .rightWrist),
        JointSegment(jointA: .rightHip, jointB: .rightKnee),
        JointSegment(jointA: .rightKnee, jointB: .rightAnkle),
        JointSegment(jointA: .leftShoulder, jointB: .rightShoulder),
        JointSegment(jointA: .leftHip, jointB: .rightHip)
    ]

    var segmentLineWidth: CGFloat = 2
    var segmentColor: UIColor = UIColor.systemTeal
    var jointRadius: CGFloat = 4
    var jointColor: UIColor = UIColor.systemPink

    func draw(poses: [Pose], on frame: CGImage) -> UIImage {
        let dstImageSize = CGSize(width: frame.width, height: frame.height)
        let dstImageFormat = UIGraphicsImageRendererFormat()

        dstImageFormat.scale = 1
        let renderer = UIGraphicsImageRenderer(size: dstImageSize, format: dstImageFormat)

        let dstImage = renderer.image { rendererContext in
            //draw(image: frame, in: rendererContext.cgContext)

            for pose in poses {
                for segment in PoseNet.jointSegments {
                    let jointA = pose[segment.jointA]
                    let jointB = pose[segment.jointB]

                    guard jointA.isValid, jointB.isValid else {
                        continue
                    }

                    drawLine(from: jointA,
                             to: jointB,
                             in: rendererContext.cgContext)
                }
                for joint in pose.joints.values.filter({ $0.isValid }) {
                    draw(circle: joint, in: rendererContext.cgContext)
                }
            }
        }
        return dstImage
    }

    func draw(image: CGImage, in cgContext: CGContext) {
        cgContext.saveGState()
        cgContext.scaleBy(x: 1.0, y: -1.0)
        let drawingRect = CGRect(x: 0, y: -image.height, width: image.width, height: image.height)

        // cgContext.draw(image, in: drawingRect)
        cgContext.restoreGState()
    }

    func drawLine(from parentJoint: Joint,
                  to childJoint: Joint,
                  in cgContext: CGContext) {
        cgContext.setStrokeColor(segmentColor.cgColor)
        cgContext.setLineWidth(segmentLineWidth)

        cgContext.move(to: parentJoint.position)
        cgContext.addLine(to: childJoint.position)
        cgContext.strokePath()
    }

    private func draw(circle joint: Joint, in cgContext: CGContext) {
        cgContext.setFillColor(jointColor.cgColor)

        let rectangle = CGRect(x: joint.position.x - jointRadius, y: joint.position.y - jointRadius,
                               width: jointRadius * 2, height: jointRadius * 2)
        cgContext.addEllipse(in: rectangle)
        cgContext.drawPath(using: .fill)
    }

    func runModel(targetView: OverlayView, pixelBuffer: CVPixelBuffer) {
        guard !isRunning else { return }

        var ciImage = CIImage(cvImageBuffer: pixelBuffer)
        ciImage = ciImage.transformed(by: ciImage.orientationTransform(for: .right))
        guard let cgImage = CIContext(options: nil).createCGImage(ciImage, from: ciImage.extent) else { return }
        queue.async {
            self.isRunning = true
            defer { self.isRunning = false }

            let input = PoseNetInput(image: cgImage, size: self.modelInputSize)
            guard let prediction = try? self.poseNetMLModel.prediction(from: input) else { return }
            let poseNetOutput = PoseNetOutput(prediction: prediction, modelInputSize: self.modelInputSize, modelOutputStride: self.outputStride)
            let poseBuilder = PoseBuilder(output: poseNetOutput, configuration: self.poseBuilderConfiguration, inputImage: cgImage)

            UIGraphicsBeginImageContext(cgImage.size)
            guard let image = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else { return }
            UIGraphicsEndImageContext()

            let uiImage = self.draw(poses: [poseBuilder.pose], on: image)
            DispatchQueue.main.async {
                targetView.image = uiImage
            }
        }
    }
}
