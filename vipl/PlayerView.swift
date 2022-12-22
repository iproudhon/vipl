//
//  PlayerView.swift
//  vipl
//
//  Created by Steve H. Jung on 12/12/22.
//

import UIKit
import AVFoundation

class PlayerView: UIView {
    
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }
}
