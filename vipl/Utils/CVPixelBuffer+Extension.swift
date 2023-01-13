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

    // image to -> [r, g, b, alpha]
    func toBytes() -> [UInt8]? {
        let ciImg = CIImage(cvImageBuffer: self)
        let ciCtx = CIContext(options: nil)
        guard let cgImg = ciCtx.createCGImage(ciImg, from: ciImg.extent) else { return nil }

        // to bytes
        guard let colorSpace = cgImg.colorSpace else { return nil }
        let count = cgImg.height * cgImg.bytesPerRow
        var data = [UInt8](repeating: 0, count: count)

        guard let cgCtx = CGContext(
            data: &data,
            width: cgImg.width,
            height: cgImg.height,
            bitsPerComponent: cgImg.bitsPerComponent,
            bytesPerRow: cgImg.bytesPerRow,
            space: colorSpace,
            bitmapInfo: cgImg.bitmapInfo.rawValue)
            else { fatalError() }
        cgCtx.draw(cgImg, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(cgImg.width), height: CGFloat(cgImg.height)))

        return data
    }

    // from depthMap
    func toFloats() -> [Float]? {
        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        CVPixelBufferLockBaseAddress(self, .readOnly)
        let src = UnsafeMutableRawPointer(CVPixelBufferGetBaseAddress(self))
        var floats = Array(repeating: Float(0), count: width * height)
        memcpy(UnsafeMutableRawPointer(mutating: floats), src, width * height * MemoryLayout<Float>.size)
        CVPixelBufferUnlockBaseAddress(self, .readOnly)
        return floats
    }

    func mirrored() -> CVPixelBuffer? {
        return transformed(transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: self.size.width, ty: 0))
    }

    func clone() -> CVPixelBuffer? {
        var _clone: CVPixelBuffer?

        let width = CVPixelBufferGetWidth(self)
        let height = CVPixelBufferGetHeight(self)
        let formatType = CVPixelBufferGetPixelFormatType(self)
        let attachments = CVBufferGetAttachments(self, .shouldPropagate)

        CVPixelBufferCreate(nil, width, height, formatType, attachments, &_clone)

        guard let clone = _clone else { return nil }

        CVPixelBufferLockBaseAddress(self, .readOnly)
        CVPixelBufferLockBaseAddress(clone, [])

        defer {
            CVPixelBufferUnlockBaseAddress(clone, [])
            CVPixelBufferUnlockBaseAddress(self, .readOnly)
        }

        let pixelBufferPlaneCount: Int = CVPixelBufferGetPlaneCount(self)
        if pixelBufferPlaneCount == 0 {
            let dest = CVPixelBufferGetBaseAddress(clone)
            let source = CVPixelBufferGetBaseAddress(self)
            let height = CVPixelBufferGetHeight(self)
            let bytesPerRowSrc = CVPixelBufferGetBytesPerRow(self)
            let bytesPerRowDest = CVPixelBufferGetBytesPerRow(clone)
            if bytesPerRowSrc == bytesPerRowDest {
                memcpy(dest, source, height * bytesPerRowSrc)
            } else {
                var startOfRowSrc = source
                var startOfRowDest = dest
                for _ in 0..<height {
                    memcpy(startOfRowDest, startOfRowSrc, min(bytesPerRowSrc, bytesPerRowDest))
                    startOfRowSrc = startOfRowSrc?.advanced(by: bytesPerRowSrc)
                    startOfRowDest = startOfRowDest?.advanced(by: bytesPerRowDest)
                }
            }
        } else {
            for plane in 0 ..< pixelBufferPlaneCount {
                let dest        = CVPixelBufferGetBaseAddressOfPlane(clone, plane)
                let source      = CVPixelBufferGetBaseAddressOfPlane(self, plane)
                let height      = CVPixelBufferGetHeightOfPlane(self, plane)
                let bytesPerRowSrc = CVPixelBufferGetBytesPerRowOfPlane(self, plane)
                let bytesPerRowDest = CVPixelBufferGetBytesPerRowOfPlane(clone, plane)

                if bytesPerRowSrc == bytesPerRowDest {
                    memcpy(dest, source, height * bytesPerRowSrc)
                } else {
                    var startOfRowSrc = source
                    var startOfRowDest = dest
                    for _ in 0..<height {
                        memcpy(startOfRowDest, startOfRowSrc, min(bytesPerRowSrc, bytesPerRowDest))
                        startOfRowSrc = startOfRowSrc?.advanced(by: bytesPerRowSrc)
                        startOfRowDest = startOfRowDest?.advanced(by: bytesPerRowDest)
                    }
                }
            }
        }
        return clone
    }
}
