//
//  PoseCollection.swift
//  vipl
//
//  Created by Steve H. Jung on 1/16/23.
//

import AVFoundation

class PoseCollection {
    var ring: RingBuffer<Golfer>!

    public static var defaultMaxCount = 240 * 60 * 5
    public var minimumScore: Float32 = 0

    @objc dynamic var count: Int = 0
    @objc dynamic var status: Int = 0   // TODO: define states
    @objc dynamic var startTime: Double = 0
    @objc dynamic var endTime: Double = 0
    @objc dynamic var currentTime: Double = 0
    @objc dynamic var duration: Double = 0
    @objc dynamic var currentFrame: Int = 0

    init(size: Int, minimumScore: Float32) {
        self.minimumScore = minimumScore
        ring = RingBuffer(count: size)
    }

    init(poser: Poser, asset: AVAsset, minimumScore: Float32) {
        self.minimumScore = minimumScore
        try? load(poser: poser, asset: asset)
    }

    func load(poser: Poser, asset: AVAsset) throws {
        let reader = try AVAssetReader(asset: asset)
        let track = asset.tracks(withMediaType: .video).first
        let trackReaderOutput = AVAssetReaderTrackOutput(track: track!, outputSettings: [String(kCVPixelBufferPixelFormatTypeKey): kCVPixelFormatType_32BGRA])
        reader.add(trackReaderOutput)
        reader.startReading()

        while let sampleBuffer = trackReaderOutput.copyNextSampleBuffer() {
            if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let (golfer, _) = try poser.estimate(on: imageBuffer)
                if var golfer = golfer {
                    golfer.time = time.seconds
                    self.append(golfer)
                }
            }
        }
        print("All loaded")
    }

    func clear(count: Int = PoseCollection.defaultMaxCount) {
        ring = RingBuffer(count: count)
        self.count = 0
        status = 0
        startTime = 0
        endTime = 0
        currentTime = 0
        duration = 0
        currentFrame = 0
    }

    // correct invalid slots, calculate velocity & acceleration
    func proc(ix: Int) {
        guard var g = ring.get(ix) else { return }

        // for each point,
        // 1. find the previous good point
        // 2. calculate velocity
        // 3. find the previous two good points
        // 4. calculate accelerations

        var pg: Golfer? = nil, ppg: Golfer? = nil
        var pi = -1, ppi = -1

        for (index, _) in GolferPart.allCases.enumerated() {
            for i in stride(from: ix-1, to: 0, by: -1) {
                if let gg = seek(to: i, moveCursor: false),
                   gg.score > minimumScore && gg.points[index]!.score > minimumScore {
                    if pi == -1 {
                        pi = i
                        pg = gg
                    } else if ppi == -1 {
                        ppi = i
                        ppg = gg
                        break
                    }
                }
            }

            // TODO: need to normalize to body unit
            if pg != nil {
                var gpt = g.points[index]!
                let pgpt = pg!.points[index]!
                let vx = (gpt.pt.x - pgpt.pt.x) / (g.time - pg!.time)
                let vy = (gpt.pt.y - pgpt.pt.y) / (g.time - pg!.time)
                g.points[index]!.vx = vx
                g.points[index]!.vy = vy

                // TODO: fill up the in-between invalid points

                if ppg != nil {
                    let ax = (gpt.vx - pgpt.vx) / (g.time - pg!.time)
                    let ay = (gpt.vy - pgpt.vy) / (g.time - pg!.time)
                    g.points[index]!.ax = ax
                    g.points[index]!.ay = ay
                }
            }
        }
        ring.set(ix, g)
    }

    func append(_ g: Golfer) {
        _ = ring.append(g)
        count = ring.count
        if count == 1 {
            startTime = g.time
            endTime = g.time
            currentTime = g.time
            duration = 0
            currentFrame = 0
        } else {
            currentTime = g.time
            endTime = g.time
            duration = endTime - startTime
            currentFrame = count - 1
        }
        proc(ix: currentFrame)
    }

    func seek(to: Double, toBefore: Bool = true, moveCursor: Bool = true) -> Golfer? {
        var l = 0, h = count - 1, m = (l + h) / 2
        while l <= h {
            m = (l + h) / 2
            if let g = ring.get(m) {
                if to.equalInMsec(to: g.time) {
                    print("XXX: found")
                    if moveCursor {
                        currentTime = g.time
                        currentFrame = m
                    }
                    return g
                } else if to < g.time {
                    h = m - 1
                } else {
                    l = m + 1
                }
            }
        }
        var g: Golfer? = nil
        if toBefore {
            if m > 0 {
                g = ring.get(m-1)
                if g != nil && moveCursor {
                    currentFrame = m-1
                }
            }
        } else {
            if m < count-1 {
                g = ring.get(m+1)
                if g != nil && moveCursor {
                    currentFrame = m+1
                }
            }
        }
        if g != nil && moveCursor {
            currentTime = g!.time
        }
        return g
    }

    func seek(to: Int, moveCursor: Bool = true) -> Golfer? {
        if to < 0 || to >= count {
            return nil
        }
        if moveCursor {
            currentFrame = to
        }
        let golfer = ring.get(to)
        if golfer != nil && moveCursor {
            currentTime = golfer!.time
        }
        return golfer
    }
}
