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
//

import UIKit

// MARK: Detection result
/// Time required to run pose estimation on one frame.
struct Times {
  var preprocessing: TimeInterval
  var inference: TimeInterval
  var postprocessing: TimeInterval
  var total: TimeInterval { preprocessing + inference + postprocessing }
}

/// An enum describing a body part (e.g. nose, left eye etc.).
enum BodyPart: String, CaseIterable {
  case nose = "nose"
  case leftEye = "left eye"
  case rightEye = "right eye"
  case leftEar = "left ear"
  case rightEar = "right ear"
  case leftShoulder = "left shoulder"
  case rightShoulder = "right shoulder"
  case leftElbow = "left elbow"
  case rightElbow = "right elbow"
  case leftWrist = "left wrist"
  case rightWrist = "right wrist"
  case leftHip = "left hip"
  case rightHip = "right hip"
  case leftKnee = "left knee"
  case rightKnee = "right knee"
  case leftAnkle = "left ankle"
  case rightAnkle = "right ankle"

  /// Get the index of the body part in the array returned by pose estimation models.
  var position: Int {
    return BodyPart.allCases.firstIndex(of: self) ?? 0
  }
}

/// A body keypoint (e.g. nose) 's detection result.
struct KeyPoint {
  var bodyPart: BodyPart = .nose
  var coordinate: CGPoint = .zero
  var score: Float32 = 0.0
}

/// A person detected by a pose estimation model.
struct Person {
  var keyPoints: [KeyPoint]
  var score: Float32
}

enum GolferPart: Int, CaseIterable {
  case nose, leftEye, rightEye, leftEar, rightEar, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle
  case wrist

  /// Get the index of the body part in the array returned by pose estimation models.
  var index: Int {
    return GolferPart.allCases.firstIndex(of: self) ?? 0
  }
}

struct GolferBodyPoint {
    // velocity & acceleration (derivative) over x and y-axis
    var part: GolferPart = .nose
    var vx: Double = 0
    var vy: Double = 0
    var ax: Double = 0
    var ay: Double = 0
    // inferred point or derived from neighbors
    var pt: CGPoint = .zero
    // inferred point
    var orgPt: CGPoint = .zero
    var score: Float32 = 0.0
}

struct Golfer {
    var time: Double = 0
    var points: [GolferBodyPoint?] = Array(repeating: nil, count: GolferPart.allCases.count)
    // distance between the centers of hips and knees
    var unit: Double = 0
    var score: Float32 = 0
}

extension GolferBodyPoint {
    init(_ p: KeyPoint) {
        part = GolferPart(rawValue: p.bodyPart.position) ?? .nose
        pt = p.coordinate
        orgPt = pt
        score = p.score
    }
}

extension CGPoint {
    func midPoint(to: CGPoint) -> CGPoint {
        return CGPoint(x: (x + to.x) / 2, y: (y + to.y) / 2)
    }
}

extension Golfer {
    init(_ p: Person, time: Double = 0) {
        self.time = time
        for (index, _) in BodyPart.allCases.enumerated() {
            points[index] = GolferBodyPoint(p.keyPoints[index])
        }
        score = p.score

        let hip = leftHip.orgPt.midPoint(to: rightHip.orgPt)
        let knee = leftKnee.orgPt.midPoint(to: rightKnee.orgPt)
        wrist = GolferBodyPoint(p.keyPoints[BodyPart.rightWrist.position])
        wrist.score = min(leftWrist.score, rightWrist.score)
        wrist.orgPt = leftWrist.orgPt.midPoint(to: rightWrist.orgPt)
        wrist.pt = wrist.orgPt
        unit = hip.distance(to: knee)
    }

    var nose: GolferBodyPoint {
        get { return points[GolferPart.nose.index]! }
        set(point) { points[GolferPart.nose.index] = point }
    }
    var leftEye: GolferBodyPoint {
        get { return points[GolferPart.leftEye.index]! }
        set(point) { points[GolferPart.leftEye.index] = point }
    }
    var rightEye: GolferBodyPoint {
        get { return points[GolferPart.rightEye.index]! }
        set(point) { points[GolferPart.rightEye.index] = point }
    }
    var leftEar: GolferBodyPoint {
        get { return points[GolferPart.leftEar.index]! }
        set(point) { points[GolferPart.leftEar.index] = point }
    }
    var rightEar: GolferBodyPoint {
        get { return points[GolferPart.rightEar.index]! }
        set(point) { points[GolferPart.rightEar.index] = point }
    }
    var leftShoulder: GolferBodyPoint {
        get { return points[GolferPart.leftShoulder.index]! }
        set(point) { points[GolferPart.leftShoulder.index] = point }
    }
    var rightShoulder: GolferBodyPoint {
        get { return points[GolferPart.rightShoulder.index]! }
        set(point) { points[GolferPart.rightShoulder.index] = point }
    }
    var leftElbow: GolferBodyPoint {
        get { return points[GolferPart.leftElbow.index]! }
        set(point) { points[GolferPart.leftElbow.index] = point }
    }
    var rightElbow: GolferBodyPoint {
        get { return points[GolferPart.rightElbow.index]! }
        set(point) { points[GolferPart.rightElbow.index] = point }
    }
    var leftWrist: GolferBodyPoint {
        get { return points[GolferPart.leftWrist.index]! }
        set(point) { points[GolferPart.leftWrist.index] = point }
    }
    var rightWrist: GolferBodyPoint {
        get { return points[GolferPart.rightWrist.index]! }
        set(point) { points[GolferPart.rightWrist.index] = point }
    }
    var leftHip: GolferBodyPoint {
        get { return points[GolferPart.leftHip.index]! }
        set(point) { points[GolferPart.leftHip.index] = point }
    }
    var rightHip: GolferBodyPoint {
        get { return points[GolferPart.rightHip.index]! }
        set(point) { points[GolferPart.rightHip.index] = point }
    }
    var leftKnee: GolferBodyPoint {
        get { return points[GolferPart.leftKnee.index]! }
        set(point) { points[GolferPart.leftKnee.index] = point }
    }
    var rightKnee: GolferBodyPoint {
        get { return points[GolferPart.rightKnee.index]! }
        set(point) { points[GolferPart.rightKnee.index] = point }
    }
    var leftAnkle: GolferBodyPoint {
        get { return points[GolferPart.leftAnkle.index]! }
        set(point) { points[GolferPart.leftAnkle.index] = point }
    }
    var rightAnkle: GolferBodyPoint {
        get { return points[GolferPart.rightAnkle.index]! }
        set(point) { points[GolferPart.rightAnkle.index] = point }
    }
    var wrist: GolferBodyPoint {
        get { return points[GolferPart.wrist.index]! }
        set(point) { points[GolferPart.wrist.index] = point }
    }
}
