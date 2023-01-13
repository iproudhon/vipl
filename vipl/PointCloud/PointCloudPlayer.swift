//
//  PointCloudPlayer.swift
//  vipl
//

import AVFoundation
import SceneKit

// TODO: obsolete, to be removed
class PointCloudCollection {
    class Frame {
        var time: CMTime
        var pointCloud: PointCloud2

        init(time: CMTime, pointCloud: PointCloud2) {
            self.time = time
            self.pointCloud = pointCloud
        }
    }

    @objc enum Status: Int {
        case stopped, playing, recording
    }

    var ring: RingBuffer<Frame>!
    var scnView: SCNView?

    @objc dynamic var count: Int = 0
    @objc dynamic var status: Status = .stopped
    @objc dynamic var startTime: CMTime = CMTime.zero
    @objc dynamic var endTime: CMTime = CMTime.zero
    @objc dynamic var currentTime: CMTime = CMTime.zero
    @objc dynamic var duration: CMTime = CMTime.zero
    @objc dynamic var currentFrame: Int = 0

    var isPlaying: Bool { return status == .playing }
    var isRecording: Bool { return status == .recording }

    init(scnView: SCNView?, count: Int) {
        ring = RingBuffer(count: count)
        self.scnView = scnView
    }

    init(scnView: SCNView?, url: URL) {
        // TODO: open url
        ring = RingBuffer(count: 1000)
        self.scnView = scnView
    }

    // player stuff
    func play() {
        if status == .playing {
            return
        } else if count == 0 {
            return
        }

        status = .playing
        if currentFrame >= count-1 {
            currentFrame = 0
        }
        showFrame()
        currentFrame += 1

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: { timer in
            if self.status != .playing {
                timer.invalidate()
            } else if self.currentFrame >= self.count - 1 {
                self.status = .stopped
                timer.invalidate()
            }
            self.showFrame()
            self.currentFrame += 1
        })
    }

    func showFrame() {
        if let view = self.scnView {
            if let node = view.scene?.rootNode.childNodes.first(where: { node in return node.name == "it" }) {
                node.removeFromParentNode()
            }
            if let frame = ring.get(self.currentFrame),
               let node = frame.pointCloud.toSCNNode() {
                node.name = "it"
                view.scene?.rootNode.addChildNode(node)
            }
        }
    }

    func stop() {
        if status == .stopped {
            return
        }
        status = .stopped
    }

    func seek(time: CMTime) -> (Int, CMTime) {
        var prev: Frame?
        for ix in 0...ring.count {
            if let frame = ring.get(ix) {
                if time == frame.time {
                    return (ix, frame.time)
                } else if time > frame.time {
                    if let prev = prev {
                        return (ix-1, prev.time)
                    } else {
                        return (ix, frame.time)
                    }
                }
                prev = frame
            }
        }
        return (ring.count-1, ring.rear?.time ?? CMTime.zero)
    }

    func seek(frame: Int) -> (Int, CMTime) {
        if frame < 0 || frame >= count {
            return (-1, CMTime.zero)
        }
        currentFrame = frame
        if let frame = ring.get(currentFrame) {
            return (currentFrame, frame.time)
        } else {
            return (-1, CMTime.zero)
        }
    }

    // recorder stuff
    func startRecording() {
        self.status = .recording
    }

    func stopRecording() {
        self.status = .stopped
    }

    func clear() {
        ring.clear()
        count = 0
        startTime = CMTime.zero
        currentTime = CMTime.zero
        endTime = CMTime.zero
        duration = CMTime.zero
        currentFrame = 0
    }

    func append(item: PointCloud2, time: CMTime) {
        if status != .recording {
            return
        }

        _ = ring.append(Frame(time: time, pointCloud: item), overwrite: true)
        count = ring.count
        currentTime = ring.rear?.time ?? CMTime.zero
        startTime = ring.front?.time ?? CMTime.zero
        endTime = currentTime
        duration = endTime - startTime
        currentFrame = count - 1
    }

    // save & load
    func save(url: URL) -> Bool {
        return false
    }

    func load(url: URL) -> Bool {
        return false
    }
}

class PointCloudPlayer: NSObject {
    var url: URL?
    private var view: SCNView?
    private var asset: PointCloudRecorder?
    private var frameTimes: [Double]?

    @objc enum Status: Int {
        case stopped, playing, recording
    }

    @objc dynamic var status: Status = .stopped
    @objc dynamic var startTime: CMTime = CMTime.zero
    @objc dynamic var currentTime: CMTime = CMTime.zero
    @objc dynamic var endTime: CMTime = CMTime.zero
    @objc dynamic var duration: CMTime = CMTime.zero
    @objc dynamic var frame: Int = 0
    @objc dynamic var count: Int = 0

    var creationDate: Date?

    var pointCloud: PointCloud2? {
        guard let asset = self.asset else { return nil }

        var cacheId: String?
        if url != nil && creationDate != nil {
            let duration = asset.endTime() - asset.startTime()
            cacheId = "\(url!.lastPathComponent):\(Int64(creationDate!.timeIntervalSince1970 * 1000) * Int64(duration * 1000)):\(asset.currentTime())"
        }
        var ptcld: PointCloud2?
        if cacheId != nil {
            ptcld = Cache.Default.get(cacheId!) as? PointCloud2
        }
        if ptcld != nil {
            return ptcld
        }

        ptcld = PointCloud2()
        guard let ptcld = ptcld,
              let info = FrameCalibrationInfo.fromJson(data: asset.info()) else {
            return nil
        }
        let intrinsics = info.calibrationIntrinsicMatrix
        ptcld.width = info.width
        ptcld.height = info.height
        let ratio = Float(info.calibrationIntrinsicMatrixReferenceDimensions.width) / Float(ptcld.width)
        ptcld.fx = intrinsics[0][0] / ratio
        ptcld.fy = intrinsics[1][1] / ratio
        ptcld.cx = intrinsics[2][0] / ratio
        ptcld.cy = intrinsics[2][1] / ratio
        ptcld.depths = Array(repeating: Float(0), count: ptcld.width * ptcld.height)
        memcpy(UnsafeMutableRawPointer(mutating: ptcld.depths), asset.depths(), ptcld.width * ptcld.height * MemoryLayout<Float>.size)
        ptcld.colors = Array(repeating: UInt8(0), count: ptcld.width * ptcld.height * 4)
        memcpy(UnsafeMutableRawPointer(mutating: ptcld.colors), asset.colors(), ptcld.width * ptcld.height * 4 * MemoryLayout<UInt8>.size)

        _ = ptcld.toSCNNode()
        if cacheId != nil {
            Cache.Default.set(cacheId!, ptcld as Any)
        }
        return ptcld
    }

    var scnNode: SCNNode? {
        guard let asset = self.asset else { return nil }

        var cacheId: String?
        if url != nil && creationDate != nil {
            let duration = asset.endTime() - asset.startTime()
            cacheId = "\(url!.lastPathComponent):\(Int64(creationDate!.timeIntervalSince1970 * 1000) * Int64(duration * 1000)):node:\(asset.currentTime())"
        }
        var node: SCNNode?
        if cacheId != nil {
            node = Cache.Default.get(cacheId!) as? SCNNode
        }
        if node != nil {
            return node
        }

        var ptcld = PointCloud2()
        guard let info = FrameCalibrationInfo.fromJson(data: asset.info()) else {
            return nil
        }
        let intrinsics = info.calibrationIntrinsicMatrix
        ptcld.width = info.width
        ptcld.height = info.height
        let ratio = Float(info.calibrationIntrinsicMatrixReferenceDimensions.width) / Float(ptcld.width)
        ptcld.fx = intrinsics[0][0] / ratio
        ptcld.fy = intrinsics[1][1] / ratio
        ptcld.cx = intrinsics[2][0] / ratio
        ptcld.cy = intrinsics[2][1] / ratio
        ptcld.depths = Array(repeating: Float(0), count: ptcld.width * ptcld.height)
        memcpy(UnsafeMutableRawPointer(mutating: ptcld.depths), asset.depths(), ptcld.width * ptcld.height * MemoryLayout<Float>.size)
        ptcld.colors = Array(repeating: UInt8(0), count: ptcld.width * ptcld.height * 4)
        memcpy(UnsafeMutableRawPointer(mutating: ptcld.colors), asset.colors(), ptcld.width * ptcld.height * 4 * MemoryLayout<UInt8>.size)

        node = ptcld.toSCNNode()
        if cacheId != nil {
            Cache.Default.set(cacheId!, node as Any)
        }
        return node
    }

    init(view: SCNView?, url: URL) {
        self.url = url
        self.view = view
        self.status = .stopped
        asset = PointCloudRecorder()
        if !asset!.open(url.path, forWrite: false) {
            asset = nil
            return
        }

        // load frame times
        frameTimes = Array(repeating: 0, count: Int(asset!.frameCount()))
        asset!.seek(0, whence: 0)
        for ix in 0..<asset!.frameCount() {
            frameTimes![Int(ix)] = asset!.currentTime() - asset!.startTime()
            asset!.nextFrame(false)
        }
        asset!.seek(0, whence: 0)

        self.startTime = CMTime.zero
        self.currentTime = CMTime.zero
        self.endTime = CMTime(seconds: (asset?.endTime() ?? 0) - (asset?.startTime() ?? 0), preferredTimescale: 600)
        self.duration = self.endTime
        self.frame = 0
        self.count = Int(asset?.frameCount() ?? 0)

        (self.creationDate, _) = FileSystemHelper.fileTimes(url: url)

        if self.count < 120 {
            PointCloud2.interlace = 1
        } else if self.count < 300 {
            PointCloud2.interlace = 2
        } else {
            PointCloud2.interlace = 4
        }
    }

    func loadPointClouds(log: ((String) -> ())? = nil) {
        var done = 0
        let startTime = Date()
        DispatchQueue.global(qos: .utility).async {
            for ix in 0..<self.count {
                DispatchQueue.global(qos: .background).async {
                    let oix = self.frame
                    objc_sync_enter(self)
                    if (self.asset?.seek(Int32(ix), whence: 0) ?? -1) != -1 {
                        _ = self.pointCloud
                    }
                    self.asset?.seek(Int32(oix), whence: 0)
                    done += 1
                    let alldone = done == self.count
                    objc_sync_exit(self)
                    if alldone {
                        let dt = Int(Date().timeIntervalSince(startTime) * 1000)
                        let msg = "loading \(self.count) point clouds done: \(dt) ms"
                        log?(msg)
                    }
                }
            }
        }
    }

    func close() {
        guard let asset = self.asset else { return }
        asset.close()
        self.asset = nil
        frameTimes = nil
    }

    func seek(frame: Int) -> Bool {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        if (asset?.seek(Int32(frame), whence: 0) ?? -1) == -1 {
            return false
        }
        self.frame = Int(asset?.frameNumber() ?? -1)
        self.currentTime = CMTime(seconds: (asset?.currentTime() ?? 0) - (asset?.startTime() ?? 0), preferredTimescale: 600)

        if let scene = view?.scene,
           let ptcld = pointCloud,
           let node = ptcld.toSCNNode() {
            node.name = "it"
            scene.rootNode.addChildNode(node)

            if let node = scene.rootNode.childNodes.first(where: { node in return node.name == "it" }) {
                node.removeFromParentNode()
            }
            node.name = "it"
            scene.rootNode.addChildNode(node)
        }
        return true
    }

    func timeToFrame(time: CMTime) -> Int {
        guard let frameTimes = frameTimes else { return 0 }
        var l = 0, h = count - 1, m = 0
        while l <= h {
            m = (l + h) / 2
            if time.seconds == frameTimes[m] {
                return m
            } else if time.seconds < frameTimes[m] {
                h = m - 1
            } else {
                l = m + 1
            }
        }
        if frameTimes[m] < time.seconds {
            return m
        } else if m > 0 {
            return m - 1
        } else {
            return m
        }
    }

    func seek(time: CMTime) -> Bool {
        return seek(frame: timeToFrame(time: time))
    }

    public func export(to: URL, startTime: CMTime, endTime: CMTime) -> Bool {
        let fromAsset = PointCloudRecorder(), toAsset = PointCloudRecorder()
        defer { fromAsset.close(); toAsset.close() }
        guard fromAsset.open(url!.path, forWrite: false),
              toAsset.open(to.path, forWrite: true) else {
            return false
        }

        // using already loaded frameTimes structure
        let startIndex = timeToFrame(time: startTime)
        var endIndex = timeToFrame(time: endTime)
        if endIndex < count - 1 {
            endIndex += 1
        }

        let currentIndex = frame
        var width = 0, height = 0
        for ix in startIndex...endIndex {
            // TODO: error handling
            fromAsset.seek(Int32(ix), whence: 0)

            // need to read width & height
            if ix == startIndex {
                guard let frameCalibrationInfo = FrameCalibrationInfo.fromJson(data: fromAsset.info()) else {
                    return false
                }
                width = frameCalibrationInfo.width
                height = frameCalibrationInfo.height
            }
            toAsset.record(fromAsset.currentTime(), info: fromAsset.info(), count: Int32(width * height), depths: fromAsset.depths(), colors: fromAsset.colors())
        }

        return true
    }
}
