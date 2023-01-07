//
//  CVPixelBuffer+Extension.swift
//  vipl
//
//  Created by Steve H. Jung on 1/7/23.
//

import Foundation
import CoreGraphics
import CoreImage

extension CVPixelBuffer {
    func transformed(transform: CGAffineTransform) -> CVPixelBuffer? {
        let ciImage = CIImage(cvPixelBuffer: self).transformed(by: transform)
        var outPixelBuffer : CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(ciImage.extent.width),
                                         Int(ciImage.extent.height),
                                         CVPixelBufferGetPixelFormatType(self),
                                         nil,
                                         &outPixelBuffer)
        guard (status == kCVReturnSuccess) else {
            return nil
        }
        let ctx = CIContext(options: nil)
        ctx.render(ciImage, to: outPixelBuffer!)
        return outPixelBuffer
    }

    func mirrored() -> CVPixelBuffer? {
        return transformed(transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: self.size.width, ty: 0))
    }
}
