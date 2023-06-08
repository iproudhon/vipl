//
//  GravityView.swift
//  vipl
//
//  Created by Steve H. Jung on 6/6/23.
//

import CoreMotion
import UIKit

class GravityView: UIView {
    var gravityVector: CMAcceleration?
    let gravityColor: CGColor = UIColor.red.cgColor
    let axisColor: CGColor = UIColor.green.cgColor
    let lineLength: CGFloat = 100

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setLineWidth(5)
        context.setAlpha(0.5)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var pt = CGPoint(x: center.x + lineLength, y: center.y)
        context.setStrokeColor(axisColor)
        context.beginPath()
        context.move(to: center)
        context.addLine(to: pt)
        context.strokePath()

        pt = CGPoint(x: center.x, y: center.y + lineLength)
        context.setStrokeColor(axisColor)
        context.beginPath()
        context.move(to: center)
        context.addLine(to: pt)
        context.strokePath()

        // Draw the gravity vector
        if let gravity = gravityVector {
            pt = CGPoint(x: center.x + CGFloat(gravity.x * lineLength), y: center.y + CGFloat(gravity.y * -lineLength))
            context.setStrokeColor(gravityColor)
            context.beginPath()
            context.move(to: center)
            context.addLine(to: pt)
            context.strokePath()

            pt = CGPoint(x: center.x + CGFloat(gravity.y * -lineLength), y: center.y + CGFloat(gravity.z * lineLength))
            context.setStrokeColor(gravityColor)
            context.beginPath()
            context.move(to: center)
            context.addLine(to: pt)
            context.strokePath()
        }
    }

    func update(gravity: CMAcceleration) {
        self.gravityVector = gravity
        self.setNeedsDisplay()
    }
}
