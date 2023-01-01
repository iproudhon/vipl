// Copyright 2021 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// =============================================================================

import AVFoundation
import UIKit
import os

/// Custom view to visualize the pose estimation result on top of the input image.
class OverlayView: UIImageView {

  // frozen poses & snaps
  private var poses = [(person: Person, time: CMTime)]()
  private var snaps = [(snap: UIImage, time: CMTime)]()

  // current time, pose & snap
  private var time: CMTime?
  private var pose: Person?
  private var snap: UIImage?

  /// Visualization configs
  private enum Config {
    static let faceColor = UIColor.orange
    static let leftColor = UIColor.systemTeal
    static let rightColor = UIColor.systemPurple
    static let dotRadius = CGFloat(5.0)
    static let line = (width: CGFloat(2.0), color: UIColor.gray)
  }

  /// List of lines connecting each part to be visualized.
  private static let lines = [
    (from: BodyPart.leftWrist, to: BodyPart.leftElbow),
    (from: BodyPart.leftElbow, to: BodyPart.leftShoulder),
    (from: BodyPart.leftShoulder, to: BodyPart.rightShoulder),
    (from: BodyPart.rightShoulder, to: BodyPart.rightElbow),
    (from: BodyPart.rightElbow, to: BodyPart.rightWrist),
    (from: BodyPart.leftShoulder, to: BodyPart.leftHip),
    (from: BodyPart.leftHip, to: BodyPart.rightHip),
    (from: BodyPart.rightHip, to: BodyPart.rightShoulder),
    (from: BodyPart.leftHip, to: BodyPart.leftKnee),
    (from: BodyPart.leftKnee, to: BodyPart.leftAnkle),
    (from: BodyPart.rightHip, to: BodyPart.rightKnee),
    (from: BodyPart.rightKnee, to: BodyPart.rightAnkle),
  ]

  /// Draw the detected keypoints on top of the input image.
  ///
  /// - Parameters:
  ///     - image: The input image.
  ///     - person: Keypoints of the person detected (i.e. output of a pose estimation model)
  func draw(at context: CGContext, person: Person) {
    guard let strokes = strokes(from: person) else { return }

    context.setLineWidth(Config.line.width)
    context.setStrokeColor(Config.line.color.cgColor)
    drawLines(at: context, lines: strokes.lines)
    context.strokePath()

    context.setLineWidth(Config.dotRadius)
    context.setStrokeColor(Config.faceColor.cgColor)
    drawDots(at: context, dots: strokes.faceDots)
    context.strokePath()
    context.setStrokeColor(Config.leftColor.cgColor)
    drawDots(at: context, dots: strokes.leftDots)
    context.strokePath()
    context.setStrokeColor(Config.rightColor.cgColor)
    drawDots(at: context, dots: strokes.rightDots)
    context.strokePath()
  }

  /// Draw the dots (i.e. keypoints).
  ///
  /// - Parameters:
  ///     - context: The context to be drawn on.
  ///     - dots: The list of dots to be drawn.
  private func drawDots(at context: CGContext, dots: [CGPoint]) {
    for dot in dots {
      let dotRect = CGRect(
        x: dot.x - Config.dotRadius / 2, y: dot.y - Config.dotRadius / 2,
        width: Config.dotRadius, height: Config.dotRadius)
      let path = CGPath(
        roundedRect: dotRect, cornerWidth: Config.dotRadius, cornerHeight: Config.dotRadius,
        transform: nil)
      context.addPath(path)
    }
  }

  /// Draw the lines (i.e. conneting the keypoints).
  ///
  /// - Parameters:
  ///     - context: The context to be drawn on.
  ///     - lines: The list of lines to be drawn.
  private func drawLines(at context: CGContext, lines: [Line]) {
    for line in lines {
      context.move(to: CGPoint(x: line.from.x, y: line.from.y))
      context.addLine(to: CGPoint(x: line.to.x, y: line.to.y))
    }
  }

  /// Generate a list of strokes to draw in order to visualize the pose estimation result.
  ///
  /// - Parameters:
  ///     - person: The detected person (i.e. output of a pose estimation model).
  private func strokes(from person: Person) -> Strokes? {
    var strokes = Strokes(faceDots: [], leftDots: [], rightDots: [], lines: [])
    // MARK: Visualization of detection result
    var bodyPartToDotMap: [BodyPart: CGPoint] = [:]
    for (index, part) in BodyPart.allCases.enumerated() {
      let position = CGPoint(
        x: person.keyPoints[index].coordinate.x,
        y: person.keyPoints[index].coordinate.y)
      bodyPartToDotMap[part] = position
      switch part {
      case .nose, .leftEye, .rightEye, .leftEar, .rightEar:
        strokes.faceDots.append(position)
      case .leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftKnee, .leftAnkle:
        strokes.leftDots.append(position)
      case .rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightKnee, .rightAnkle:
        strokes.rightDots.append(position)
      }
    }

    do {
      try strokes.lines = OverlayView.lines.map { map throws -> Line in
        guard let from = bodyPartToDotMap[map.from] else {
          throw VisualizationError.missingBodyPart(of: map.from)
        }
        guard let to = bodyPartToDotMap[map.to] else {
          throw VisualizationError.missingBodyPart(of: map.to)
        }
        return Line(from: from, to: to)
      }
    } catch VisualizationError.missingBodyPart(let missingPart) {
      os_log("Visualization error: %s is missing.", type: .error, missingPart.rawValue)
      return nil
    } catch {
      os_log("Visualization error: %s", type: .error, error.localizedDescription)
      return nil
    }
    return strokes
  }

  func pushPose(pose: Person?, snap: UIImage?, time: CMTime) {
    if pose != nil {
      poses.append((person: pose!, time: time))
    }
    if snap != nil {
      snaps.append((snap: snap!, time: time))
    }
  }

  func resetPoses() {
    poses = []
    snaps = []
  }

  func draw(size: CGSize) {
    UIGraphicsBeginImageContext(size)
    guard let context = UIGraphicsGetCurrentContext() else {
      fatalError("set current context faild")
    }

    for img in self.snaps {
      img.snap.draw(at: .zero)
    }
    if let snap = snap {
      snap.draw(at: .zero)
    }
    for pos in self.poses {
        draw(at: context, person: pos.person)
    }
    if let pose = pose {
      draw(at: context, person: pose)
    }

    guard let image = UIGraphicsGetImageFromCurrentImageContext() else { fatalError() }
    self.image = image
    UIGraphicsEndImageContext()
  }

  func setPose(_ pose: Person?, _ time: CMTime) {
    self.pose = pose
    self.time = time
  }

  func setSnap(_ snap: UIImage?, _ time: CMTime) {
    self.snap = snap
    self.time = time
  }
}

/// The strokes to be drawn in order to visualize a pose estimation result.
fileprivate struct Strokes {
  var faceDots: [CGPoint]
  var leftDots: [CGPoint]
  var rightDots: [CGPoint]
  var lines: [Line]
}

/// A straight line.
fileprivate struct Line {
  let from: CGPoint
  let to: CGPoint
}

fileprivate enum VisualizationError: Error {
  case missingBodyPart(of: BodyPart)
}
