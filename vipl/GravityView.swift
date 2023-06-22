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

    func rotate_0(x: CGFloat, y: CGFloat, pitch: Double, roll: Double) -> (CGFloat, CGFloat) {
        let x2 = x - bounds.midX
        let y2 = y - bounds.midY
        var newX = x2 * CGFloat(cos(pitch)) - y2 * CGFloat(sin(pitch))
        var newY = x2 * CGFloat(sin(pitch)) + y2 * CGFloat(cos(pitch))
        newX += bounds.midX
        newY += bounds.midY
        return (newX, newY)
    }

    func rotate(x: CGFloat, y: CGFloat, z: CGFloat, pitch: Double, roll: Double) -> (CGFloat, CGFloat) {
        var transform = CATransform3DIdentity
        transform = CATransform3DRotate(transform, pitch, 0, 0, 1)
        transform = CATransform3DRotate(transform, roll, 1, 0, 0)

        var x = x - bounds.midX, y = y - bounds.midY, z = z, w = CGFloat(1)
        let nx = transform.m11 * x + transform.m21 * y + transform.m31 * z + transform.m41 * w
        let ny = transform.m12 * x + transform.m22 * y + transform.m32 * z + transform.m42 * w
        _ = transform.m13 * x + transform.m23 * y + transform.m33 * z + transform.m43 * w
        let nw = transform.m14 * x + transform.m24 * y + transform.m34 * z + transform.m44 * w

        return (nx/nw + bounds.midX, ny/nw + bounds.midY)
    }


    override func draw(_ rect: CGRect) {
        super.draw(rect)

        var pitch = Double(0), roll = Double(0)
        var deltaX: CGFloat = 0, deltaY: CGFloat = 0

        // pitch and roll from the gravity vector
        // pitch is around z axis, roll is around x axis and vertical is -90 degrees
        if let gravity = gravityVector {
            pitch = atan2(-gravity.y, gravity.x) - .pi / 2.0
            roll = atan2(gravity.y, gravity.z) + .pi / 2.0

            let delta = bounds.midY * CGFloat(sin(roll))
            deltaX = delta * CGFloat(sin(-pitch))
            deltaY = delta * CGFloat(cos(-pitch))

            // let pitchD = pitch * 180 / .pi, rollD = roll * 180 / .pi
            // print("XXX: pitch=\(String(format: "%.2f", pitchD)) roll=\(String(format: "%.2f", rollD))")
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
        // vanishing perpendicular lines
        for i in -2..<13 {
            let (x1, y1) = rotate(x: CGFloat(i) * bounds.maxX / 10, y: bounds.maxY, z: 0, pitch: pitch, roll: roll)
            context.move(to: CGPoint(x: x1, y: y1))
            context.addLine(to: CGPoint(x: bounds.midX + deltaX, y: bounds.midY + deltaY))
        }
        // horizontal bars
        for i in 0...5 {
            var x1 = CGFloat(0), y1 = CGFloat(i) * bounds.maxY / 10 + bounds.midY, x2 = CGFloat(bounds.maxX), y2 = y1
            (x1, y1) = rotate(x: x1, y: y1, z: 0, pitch: pitch, roll: roll)
            (x2, y2) = rotate(x: x2, y: y2, z: 0, pitch: pitch, roll: roll)
            context.move(to: CGPoint(x: x1, y: y1))
            context.addLine(to: CGPoint(x: x2, y: y2))
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
