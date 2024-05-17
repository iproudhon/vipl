//
//  CaptureViewController+PoseTrigger.swift
//  vipl
//
//  Created by Steve H. Jung on 12/28/23.
//

import Foundation

class PoseChecker {
    private var lastTriggerTime: Date?
    private var lastSuccessTime: Date?
    private let continuousSuccessDuration: TimeInterval = 0.5 // 1 second
    private let inactivityThreshold: TimeInterval = 3.0 // 3 seconds

    func isXMark(leftWrist: CGPoint, leftElbow: CGPoint, leftShoulder: CGPoint, rightWrist: CGPoint, rightElbow: CGPoint, rightShoulder: CGPoint) -> Bool {
        let shoulderDist = euclideanDistance(leftShoulder, rightShoulder)
        let wristDist = euclideanDistance(leftWrist, rightWrist)
        let xMinShoulder = min(leftShoulder.x, rightShoulder.x)
        let xMaxShoulder = max(leftShoulder.x, rightShoulder.x)

        return xMinShoulder < leftWrist.x && leftWrist.x < xMaxShoulder && xMinShoulder < rightWrist.x && rightWrist.x < xMaxShoulder && abs(leftShoulder.x - leftElbow.x) < abs(leftShoulder.x - leftWrist.x) && abs(rightShoulder.x - rightElbow.x) < abs(rightShoulder.x - rightWrist.x) && min(leftWrist.y, rightWrist.y) < max(leftElbow.y, rightElbow.y) && shoulderDist > wristDist * 3
    }

    func euclideanDistance(_ point1: CGPoint, _ point2: CGPoint) -> CGFloat {
        return sqrt(pow(point1.x - point2.x, 2) + pow(point1.y - point2.y, 2))
    }

    func isXPose(golfer: Golfer) -> Int {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        guard golfer.leftWrist.score >= 0.3 && golfer.leftElbow.score >= 0.3 && golfer.leftShoulder.score >= 0.3 && golfer.rightWrist.score >= 0.3 && golfer.rightElbow.score >= 0.3 && golfer.rightShoulder.score >= 0.3 else {
            return 0
        }

        let now = Date()

        // Reset interval start time if inactivity threshold is reached
        if let lastTriggerTime = lastTriggerTime, now.timeIntervalSince(lastTriggerTime) <= inactivityThreshold {
            return 0
        }

        let success = self.isXMark(leftWrist: golfer.leftWrist.pt, leftElbow: golfer.leftElbow.pt, leftShoulder: golfer.leftShoulder.pt, rightWrist: golfer.rightWrist.pt, rightElbow: golfer.rightElbow.pt, rightShoulder: golfer.rightShoulder.pt)
        if !success {
            self.lastSuccessTime = nil
            return 0
        }

        if let lastSuccessTime = self.lastSuccessTime,
           now.timeIntervalSince(lastSuccessTime) >= continuousSuccessDuration {
            self.lastSuccessTime = nil
            self.lastTriggerTime = now
            return 1
        }
        if self.lastSuccessTime == nil {
            self.lastSuccessTime = now
            return 2
        }
        return 0
    }
}
