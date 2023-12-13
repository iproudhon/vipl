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
    var reverse = false
    let gravityColor: CGColor = UIColor.red.cgColor
    let axisColor: CGColor = UIColor.green.cgColor
    let lineLength: CGFloat = 100

    func getOrientation() -> UIInterfaceOrientation {
        return self.window?.windowScene?.interfaceOrientation ?? .portrait
    }

    func perspectiveProjectionMatrix(videoFieldOfView: Double, aspect: Double) -> CATransform3D {
        let fov = videoFieldOfView * .pi / 180.0
        let yScale = 1 / tan(fov / 2.0)
        let xScale = yScale / aspect
        let zNear: Double = 0.1, zFar: Double = 1000.0
        let zRange = zNear - zFar
        // let zScale = (zFar + zNear) / zRange
        // let wzScale = 2 * zFar * zNear / zRange
        let zScale = -zFar / (zFar - zNear)
        let wzScale = -zFar * zNear / (zFar - zNear)
        let transform = CATransform3D(m11: xScale, m12: 0, m13: 0, m14: 0,
                                      m21: 0, m22: yScale, m23: 0, m24: 0,
                                      m31: 0, m32: 0, m33: zScale, m34: -1,
                                      m41: 0, m42: 0, m43: wzScale, m44: 0)
        return transform
    }

    /*
     void setProjectionMatrix(const float &angleOfView, const float &near, const float &far, Matrix44f &M)
     {
         // set the basic projection matrix
         float scale = 1 / tan(angleOfView * 0.5 * M_PI / 180);
         M[0][0] = scale;  //scale the x coordinates of the projected point
         M[1][1] = scale;  //scale the y coordinates of the projected point
         M[2][2] = -far / (far - near);  //used to remap z to [0,1]
         M[3][2] = -far * near / (far - near);  //used to remap z [0,1]
         M[2][3] = -1;  //set w = -z
         M[3][3] = 0;



         out.x   = in.x * M[0][0] + in.y * M[1][0] + in.z * M[2][0] + /* in.z = 1 */ M[3][0];
         out.y   = in.x * M[0][1] + in.y * M[1][1] + in.z * M[2][1] + /* in.z = 1 */ M[3][1];
         out.z   = in.x * M[0][2] + in.y * M[1][2] + in.z * M[2][2] + /* in.z = 1 */ M[3][2];
         float w = in.x * M[0][3] + in.y * M[1][3] + in.z * M[2][3] + /* in.z = 1 */ M[3][3];
     }
     */

    func project(transform: CATransform3D, x: Double, y: Double, z: Double) -> (x: Double, y: Double, z: Double) {
        let x = x - bounds.midX, y = y - bounds.midY, z = z, w = CGFloat(1)
        let nx = transform.m11 * x + transform.m21 * y + transform.m31 * z + transform.m41 * w
        let ny = transform.m12 * x + transform.m22 * y + transform.m32 * z + transform.m42 * w
        let nz = transform.m13 * x + transform.m23 * y + transform.m33 * z + transform.m43 * w
        let nw = transform.m14 * x + transform.m24 * y + transform.m34 * z + transform.m44 * w

        return (nx/nw + bounds.midX, ny/nw + bounds.midY, nz/nw)
    }

    func rotate(x: CGFloat, y: CGFloat, z: CGFloat, pitch: Double, roll: Double) -> (CGFloat, CGFloat) {
        var transform = CATransform3DIdentity
        transform = CATransform3DRotate(transform, pitch, 0, 0, 1)
        transform = CATransform3DRotate(transform, roll, 1, 0, 0)

        let (nx, ny, _) = project(transform: transform, x: x, y: y, z: z)
        return (nx, ny)

        /*
        let x = x - bounds.midX, y = y - bounds.midY, z = z, w = CGFloat(1)
        let nx = transform.m11 * x + transform.m21 * y + transform.m31 * z + transform.m41 * w
        let ny = transform.m12 * x + transform.m22 * y + transform.m32 * z + transform.m42 * w
        _ = transform.m13 * x + transform.m23 * y + transform.m33 * z + transform.m43 * w
        let nw = transform.m14 * x + transform.m24 * y + transform.m34 * z + transform.m44 * w

        return (nx/nw + bounds.midX, ny/nw + bounds.midY)
         */
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        var pitch = Double(0), roll = Double(0)
        var deltaX: CGFloat = 0, deltaY: CGFloat = 0

        // pitch and roll from the gravity vector
        // pitch is around z axis, roll is around x axis and vertical is -90 degrees
        var gx = Double(0), gy = Double(0), gz = Double(0)
        if let gravity = gravityVector {
            gz = gravity.z
            switch getOrientation() {
            case .portrait, .unknown:
                gx = gravity.x
                gy = gravity.y
            case .portraitUpsideDown:
                gx = gravity.x
                gy = -gravity.y
            case .landscapeLeft:
                gx = gravity.y
                gy = -gravity.x
            case .landscapeRight:
                gx = -gravity.y
                gy = gravity.x
            @unknown default:
                fatalError()
            }

            if self.reverse {
                pitch = 0
                roll = 0
                deltaX = 0
                deltaY = 0
            } else {
                pitch = atan2(-gy, gx) - .pi / 2.0
                roll = atan2(gy, gz) + .pi / 2.0

                let delta = bounds.midY * CGFloat(sin(roll))
                deltaX = delta * CGFloat(sin(-pitch))
                deltaY = delta * CGFloat(cos(-pitch))
            }

            // let pitchD = pitch * 180 / .pi, rollD = roll * 180 / .pi
            // print("XXX: pitch=\(String(format: "%.2f", pitchD)) roll=\(String(format: "%.2f", rollD))")
        }

        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setLineWidth(5)
        context.setAlpha(0.5)

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var pt = CGPoint(x: center.x + lineLength, y: center.y)
        context.beginPath()
        context.setStrokeColor(!self.reverse ? axisColor : gravityColor)
        context.move(to: pt)
        context.addLine(to: center)
        pt = CGPoint(x: center.x, y: center.y + lineLength)
        context.addLine(to: pt)
        context.strokePath()

        context.beginPath()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2)
        context.setAlpha(0.3)
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
        if gravityVector != nil {
            context.beginPath()
            context.setLineWidth(5)
            context.setAlpha(0.5)

            pt = CGPoint(x: center.x + CGFloat(gx * lineLength), y: center.y + CGFloat(gy * -lineLength))
            context.setStrokeColor(!self.reverse ? gravityColor : axisColor)
            context.move(to: pt)
            context.addLine(to: center)
            pt = CGPoint(x: center.x + CGFloat(gy * -lineLength), y: center.y + CGFloat(gz * lineLength))
            context.addLine(to: pt)

            context.strokePath()
        }

/*
        let m = perspectiveProjectionMatrix(videoFieldOfView: 70.0, aspect: 1.0)
        let (x1, y1, z1) = project(transform: m, x: 0, y: 0, z: 0.1)
        print("XXX: \(x1) \(y1) \(z1)")
 */
    }

    func update(gravity: CMAcceleration, reverse: Bool = false) {
        self.gravityVector = gravity
        self.reverse = reverse
        self.setNeedsDisplay()
    }
}
