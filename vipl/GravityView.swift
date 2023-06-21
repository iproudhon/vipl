//
//  GravityView.swift
//  vipl
//
//  Created by Steve H. Jung on 6/6/23.
//

import CoreMotion
import UIKit
import simd

class GravityView: UIView {
    var gravityVector: CMAcceleration?
    let gravityColor: CGColor = UIColor.red.cgColor
    let axisColor: CGColor = UIColor.green.cgColor
    let lineLength: CGFloat = 100

    func rotateByPitch(x: CGFloat, y: CGFloat, pitch: Double) -> (CGFloat, CGFloat) {
        let x2 = x - bounds.midX
        let y2 = y - bounds.midY
        var newX = x2 * CGFloat(cos(pitch)) - y2 * CGFloat(sin(pitch))
        var newY = x2 * CGFloat(sin(pitch)) + y2 * CGFloat(cos(pitch))
        newX += bounds.midX
        newY += bounds.midY
        return (newX, newY)
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        var deltaX: CGFloat = 0, deltaY: CGFloat = 0, pitch: Double = 0

        // pitch and roll from the gravity vector
        // pitch is around z axis, roll is around x axis and vertical is -90 degrees
        if let gravity = gravityVector {
            pitch = atan2(-gravity.x, sqrt(gravity.y * gravity.y + gravity.z * gravity.z))
            let roll = atan2(gravity.y, gravity.z)

            // Convert to degrees
            let pitchDegrees = pitch * 180.0 / .pi
            let rollDegrees = roll * 180.0 / .pi

            deltaY = bounds.midY * CGFloat(sin(roll + .pi / 2.0))
            deltaX = bounds.midX * CGFloat(sin(pitch))
        }

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setLineWidth(5)
        context.setAlpha(0.5)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var pt = CGPoint(x: center.x + lineLength, y: center.y)
        context.beginPath()
        context.setStrokeColor(axisColor)
        context.move(to: pt)
        context.addLine(to: center)
        pt = CGPoint(x: center.x, y: center.y + lineLength)
        context.addLine(to: pt)
        context.strokePath()

        context.beginPath()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2)
        context.setAlpha(0.5)
        for i in -2..<13 {
            let (x, y) = rotateByPitch(x: CGFloat(i) * bounds.maxX / 10, y: bounds.maxY, pitch: pitch)
            context.move(to: CGPoint(x: x, y: y))
            context.addLine(to: CGPoint(x: bounds.midX + deltaX, y: bounds.midY + deltaY))
        }
        context.strokePath()

        // Draw the gravity vector
        if let gravity = gravityVector {
            context.beginPath()
            context.setLineWidth(5)
            context.setAlpha(0.5)

            pt = CGPoint(x: center.x + CGFloat(gravity.x * lineLength), y: center.y + CGFloat(gravity.y * -lineLength))
            context.setStrokeColor(gravityColor)
            context.move(to: pt)
            context.addLine(to: center)
            pt = CGPoint(x: center.x + CGFloat(gravity.y * -lineLength), y: center.y + CGFloat(gravity.z * lineLength))
            context.addLine(to: pt)

            context.strokePath()
        }
    }

    func update(gravity: CMAcceleration) {
        self.gravityVector = gravity
        self.setNeedsDisplay()
    }
}
