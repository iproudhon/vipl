//
//  PointCloud.swift
//  vipl
//

import ARKit
import MetalKit

struct FrameCalibrationInfo : Codable {
    var width: Int = 0
    var height: Int = 0
    var calibrationIntrinsicMatrix: [[Float]] = [[]]
    var calibrationPixelSize: Float = 0.0
    var calibrationIntrinsicMatrixReferenceDimensions: CGSize = CGSize()
    var calibrationLensDistortionCenter: CGPoint = CGPoint()
    var calibrationLensDistortionLookupTable: [Float] = []
    var calibrationInverseLensDistortionLookupTable: [Float] = []
    var cameraImageResolution: CGSize = CGSize()
    var cameraTransform: [[Float]] = [[]]
    var cameraIntrinsics: [[Float]] = [[]]
    var cameraProjectionMatrix: [[Float]] = [[]]
    var cameraViewMatrix: [[Float]] = [[]]
}

extension FrameCalibrationInfo {
    public static func toFloats(withSimd3x3: simd_float3x3) -> [[Float]] {
        let floats = (0 ..< 3).map{ x in
            (0 ..< 3).map{ y in withSimd3x3[x][y] }
        }
        return floats
    }

    public static func toFloats(withSimd4x4: simd_float4x4) -> [[Float]] {
        let floats = (0 ..< 4).map{ x in
            (0 ..< 4).map{ y in withSimd4x4[x][y] }
        }
        return floats
    }

    public static func toSimd3x3(_ data: [[Float]]) -> simd_float3x3 {
        return simd_float3x3(
            simd_make_float3(data[0][0], data[0][1], data[0][2]),
            simd_make_float3(data[1][0], data[1][1], data[1][2]),
            simd_make_float3(data[2][0], data[2][1], data[2][2]))
    }

    public static func toSimd4x4(_ data: [[Float]]) -> simd_float4x4 {
        return simd_float4x4(
            simd_make_float4(data[0][0], data[0][1], data[0][2], data[0][3]),
            simd_make_float4(data[1][0], data[1][1], data[1][2], data[1][3]),
            simd_make_float4(data[2][0], data[2][1], data[2][2], data[2][3]),
            simd_make_float4(data[3][0], data[3][1], data[3][2], data[3][3]))
    }

    public func toJson() -> String? {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    public static func fromJson(data: String) -> FrameCalibrationInfo? {
        do {
            let jsonData = data.data(using: .utf8)!
            let decoder = JSONDecoder()
            let fci = try decoder.decode(FrameCalibrationInfo.self, from: jsonData)
            return fci
        } catch {
            print("fromJson failed: \(error)")
            return nil
        }
    }
}

struct PointCloudVertex {
    var x: Float, y: Float, z: Float, r: Float, g: Float, b: Float
}

extension PointCloudVertex {
    init() { x = 0; y = 0; z = 0; r = 0; g = 0; b = 0 }
}

@objc class PointCloud: NSObject {
    var vtxs: [PointCloudVertex] = []
    var info = FrameCalibrationInfo()
    var depths: [Float] = []        // depths
    var colors: [UInt8] = []        // argb data

    override init() {}

    init(vtxs: [PointCloudVertex]) {
        self.vtxs = vtxs
    }

    init(points: [SCNVector3], colors: [UInt8], depthTrunc: Float) {
        self.vtxs = []
        for i in 0..<points.count {
            if depthTrunc > 0 && points[i].z > depthTrunc {
                continue
            }
            self.vtxs.append(PointCloudVertex(x: Float(points[i].x), y: Float(points[i].y), z: Float(points[i].z), r: Float(colors[i * 3 + 0]) / 255.0, g: Float(colors[i * 3 + 1]) / 255.0, b: Float(colors[i * 3 + 2]) / 255.0))
        }
    }

    public func transform(org: simd_float4x4, curr: simd_float4x4) {
        let inv = curr.inverse
        self.vtxs.enumerated().forEach {
            let ix = $0, v = $1
            var pt = inv * simd_float4(x: v.x, y: v.y, z: v.z, w: 1.0)
            pt = org * pt
            self.vtxs[ix].x = pt.x
            self.vtxs[ix].y = pt.y
            self.vtxs[ix].z = pt.z
        }
    }

    public func toSCNNode() -> SCNNode {
        let vertices = NSData(bytes: vtxs, length: MemoryLayout<PointCloudVertex>.size * vtxs.count)
        let vertexSource = SCNGeometrySource(
            data: vertices as Data,
            semantic: SCNGeometrySource.Semantic.vertex,
            vectorCount: vtxs.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<PointCloudVertex>.size
        )
        let colorSource = SCNGeometrySource(
            data: vertices as Data,
            semantic: SCNGeometrySource.Semantic.color,
            vectorCount: vtxs.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: MemoryLayout<Float>.size * 3,
            dataStride: MemoryLayout<PointCloudVertex>.size
        )
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: vtxs.count,
            bytesPerIndex: MemoryLayout<Int>.size
        )
        element.pointSize = 1
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 7
        let geom = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        return SCNNode(geometry: geom)
    }

    public func toPly() -> String {
        var out = ""
        out.append("""
ply
format ascii 1.0
element vertex \(self.vtxs.count)
property double x
property double y
property double z
property uchar red
property uchar green
property uchar blue
end_header

"""
        )
        self.vtxs.enumerated().forEach {
            let v = $1
            let r = Int(v.r * 255.0), g = Int(v.g * 255.0), b = Int(v.b * 255.0)
            out.append("\(v.x) \(v.y) \(v.z) \(r) \(g) \(b)\n")
        }
        return out
    }

    public func toDepthImage() -> CGImage {
        let width = info.width, height = info.height
        var buf = Array<UInt16>(repeating: 0, count: width * height)
        self.depths.enumerated().forEach {
            var v = $1
            if v.isNaN || v > 65.535 {
                v = 65.535 * 1000.0
            } else {
                v *= 1000.0
            }
            buf[$0] = UInt16(v)
        }
        let cgImage = buf.withUnsafeMutableBytes{ (ptr) -> CGImage in
            let ctx = CGContext(
                data: ptr.baseAddress,
                width: width, height: height,
                bitsPerComponent: 16,
                bytesPerRow: width * 2,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageByteOrderInfo.order16Little.rawValue + CGImageAlphaInfo.none.rawValue)!
            return ctx.makeImage()!
        }
        return cgImage
    }

    public func toColorImage() -> CGImage {
        let width = info.width, height = info.height
        let cgImage = self.colors.withUnsafeMutableBytes{ (ptr) -> CGImage in
            let ctx = CGContext(
                data: ptr.baseAddress,
                width: width, height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            return ctx.makeImage()!
        }
        return cgImage
    }

    public static func buildNode(points: [SCNVector3], colors: [UInt8]) -> SCNNode {
        var vtxs = Array(repeating: PointCloudVertex(x: 0, y: 0, z: 0, r: 0, g: 0, b: 0), count: points.count)

        for i in 0..<points.count {
            vtxs[i].x = Float(points[i].x)
            vtxs[i].y = Float(points[i].y)
            vtxs[i].z = Float(points[i].z)
            vtxs[i].r = Float(colors[i * 3 + 0]) / 255.0
            vtxs[i].g = Float(colors[i * 3 + 1]) / 255.0
            vtxs[i].b = Float(colors[i * 3 + 2]) / 255.0
        }

        let vertices = NSData(bytes: vtxs, length: MemoryLayout<PointCloudVertex>.size * vtxs.count)
        let positionSource = SCNGeometrySource(
            data: vertices as Data,
            semantic: SCNGeometrySource.Semantic.vertex,
            vectorCount: vtxs.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<PointCloudVertex>.size
        )
        let colorSource = SCNGeometrySource(
            data: vertices as Data,
            semantic: SCNGeometrySource.Semantic.color,
            vectorCount: vtxs.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: MemoryLayout<Float>.size * 3,
            dataStride: MemoryLayout<PointCloudVertex>.size
        )
        let element = SCNGeometryElement(
            data: nil,
            primitiveType: .point,
            primitiveCount: vtxs.count,
            bytesPerIndex: MemoryLayout<Int>.size
        )
        element.pointSize = 1
        element.minimumPointScreenSpaceRadius = 1
        element.maximumPointScreenSpaceRadius = 7
        let geom = SCNGeometry(sources: [positionSource, colorSource], elements: [element])
        return SCNNode(geometry: geom)
    }

    public static func buildAxes() -> SCNNode {
        let count = 500, inc = Float(0.001)
        var points: [SCNVector3] = []
        var colors: [UInt8] = []

        for i in 0..<count {
            let l = Float(i) * inc
            points.append(contentsOf: [ SCNVector3(l, 0, 0), SCNVector3(-l, 0, 0),
                                        SCNVector3(0, l, 0), SCNVector3(0, -l, 0),
                                        SCNVector3(0, 0, l), SCNVector3(0, 0, -l) ])
            colors.append(contentsOf: [ 255, 0, 0,  255, 0, 255,
                                        0, 255, 0,  255, 255, 0,
                                        0, 0, 255,  0, 255, 255 ])
        }
        return PointCloud.init(points: points, colors: colors, depthTrunc: 0).toSCNNode()
    }

    public static func buildSquareNode(width: Int, inc: Float, color: [UInt8], depthTrunc: Float) -> SCNNode {
        var points = Array(repeating: SCNVector3(0, 0, 0), count: width * width)
        var colors: [UInt8] = Array(repeating: 0, count: width * width * 3)

        for y in 0..<width {
            for x in 0..<width {
                let ix = y * width + x
                points[ix].x = Float(x) * inc
                points[ix].y = Float(y) * inc
                points[ix].z = 0
                colors[ix*3+0] = color[0]
                colors[ix*3+1] = color[1]
                colors[ix*3+2] = color[2]
            }
        }

        return PointCloud.init(points: points, colors: colors, depthTrunc: depthTrunc).toSCNNode()
    }

    public static func buildDistortionLookupTable(width: Int, height: Int, ox: Float, oy: Float, lookupTable: Data) -> [Int] {

        // to [Float] first
        let count = lookupTable.count / MemoryLayout<Float>.stride
        var table = Array<Float>(repeating: 0, count: count)
        _ = table.withUnsafeMutableBytes { lookupTable.copyBytes(to: $0) }
        var inverseTable: [Int] = Array(repeating: 0, count: width * height)
        let xmax = Float(max(ox, Float(width) - ox)), ymax = Float(max(oy, Float(height) - oy))
        let rmax = sqrtf(xmax * xmax + ymax * ymax)

        for i in 0..<width*height {
            let x = Float(i % width) - ox, y = Float(i / width) - oy
            let r = sqrtf(x * x + y * y)
            var mag: Float = 0
            if r >= rmax {
                mag = table[count - 1]
            } else {
                let ixf = r * Float(count - 1) / rmax
                let ixi = Int(ixf)
                let diff = ixf - Float(ixi)
                let mag_1 = table[ixi], mag_2 = table[ixi + 1]
                mag = (1.0 - diff) * mag_1 + diff * mag_2
            }
            let nx = Int((ox + x + mag * x).rounded()), ny = Int((oy + y + mag * y).rounded())
            if nx < 0 || nx >= width || ny < 0 || ny >= height {
                inverseTable[i] = -1
            } else {
                inverseTable[i] = ny * width + nx
            }
        }
        return inverseTable
    }

    public static func captureImageData(image: CVPixelBuffer, width: Int, height: Int) -> [UInt8]? {
        // resize
        let ow = CVPixelBufferGetWidth(image), oh = CVPixelBufferGetHeight(image)
        let scalex = Float(width) / Float(ow), scaley = Float(height) / Float(oh)
        let ciImg = CIImage(cvPixelBuffer: image).transformed(by: CGAffineTransform(scaleX: CGFloat(scalex), y: CGFloat(scaley)))

        // to CGImage
        let ciContext = CIContext(options: nil)
        guard let cgImg = ciContext.createCGImage(ciImg, from: ciImg.extent) else { fatalError() }

        // to bytes
        guard let colorSpace = cgImg.colorSpace else { return nil }
        let count = cgImg.height * cgImg.bytesPerRow
        var data = [UInt8](repeating: 0, count: count)

        guard let cgContext = CGContext(
            data: &data,
            width: cgImg.width,
            height: cgImg.height,
            bitsPerComponent: cgImg.bitsPerComponent,
            bytesPerRow: cgImg.bytesPerRow,
            space: colorSpace,
            bitmapInfo: cgImg.bitmapInfo.rawValue)
            else { fatalError() }
        cgContext.draw(cgImg, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(cgImg.width), height: CGFloat(cgImg.height)))

        return data
    }

    public static func capturePointCloud(depthData: AVDepthData, image: CVPixelBuffer, depthTrunc: Float) -> PointCloud? {
        // frame.camera: ARCamera
        // frame.capturedDepthData: AVDepthData
        //   .depthMap: CVPixelBuffer
        //   .confidenceMap: CVPixelBuffer
        // frame.capturedImage: CVPixelBuffer

        guard let calibrationData = depthData.cameraCalibrationData else { return nil }

        let ptcld = PointCloud.init()

        // intrinsics from depth data
        let intrinsics = calibrationData.intrinsicMatrix
        let width = CVPixelBufferGetWidth(depthData.depthDataMap)
        let height = CVPixelBufferGetHeight(depthData.depthDataMap)
        let ratio = Float(calibrationData.intrinsicMatrixReferenceDimensions.width) / Float(width)
        let fx = intrinsics.columns.0[0] / ratio, fy = intrinsics.columns.1[1] / ratio
        let cx = intrinsics.columns.2[0] / ratio, cy = intrinsics.columns.2[1] / ratio
        let lx = Float(calibrationData.lensDistortionCenter.x) / ratio
        let ly = Float(calibrationData.lensDistortionCenter.y) / ratio
        let inverseTable = buildDistortionLookupTable(width: width, height: height, ox: lx, oy: ly, lookupTable: calibrationData.lensDistortionLookupTable!)
        ptcld.vtxs = []

        var depths = depthData.depthDataMap
        if depthData.depthDataType != kCVPixelFormatType_DepthFloat32 {
            depths = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32).depthDataMap
        }

        CVPixelBufferLockBaseAddress(depths, .readOnly)
        CVPixelBufferLockBaseAddress(image, .readOnly)
        let pixels = UnsafeMutableBufferPointer(
            start: unsafeBitCast(CVPixelBufferGetBaseAddress(depths),
                                 to: UnsafeMutablePointer<Float32>.self),
            count: width * height)
        ptcld.colors = captureImageData(image: image, width: width, height: height) ?? []
        CVPixelBufferUnlockBaseAddress(image, .readOnly)
        ptcld.depths = Array(repeating: 0, count: width * height)

        for i in 0..<width*height {
            ptcld.depths[i] = pixels[i]
            let ix = inverseTable[i]
            if ix != -1 {   // rectilinear image
                var z = pixels[ix]
                if depthTrunc == 0 || z < depthTrunc {
                    var u = Float(ix % width), v = Float(ix / width)
                    // flip x & z
                    u = Float(width) - u
                    z = -z
                    let pt = simd_float4((u - cx) * z / fx, (v - cy) * z / fy, z, 1.0)
                    let cix = ix * 4
                    let r = ptcld.colors[cix+0], g = ptcld.colors[cix+1], b = ptcld.colors[cix+2]
                    ptcld.vtxs.append(PointCloudVertex(x: pt[0], y: pt[1], z: pt[2], r: Float(r) / 255.0, g: Float(g) / 255.0, b: Float(b) / 255.0))
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(depthData.depthDataMap, .readOnly)
        return ptcld
    }
}
